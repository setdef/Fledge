/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: MIT-0
 */

/*
 * A game's smallest loop on SDL3, driven from Ruby (ADR 025): SdlDemo.run
 * opens a full-screen window, and on every frame hands the block the
 * frame's number, the window's size in pixels, and the touches SDL saw
 * since the last frame, then draws what the block answers: a background
 * color and a white square at a point. SdlDemo.stack says how deep the
 * calling thread's stack is and whether it is the process's main thread,
 * which is where SDL's video must run on iOS.
 */
#include <ruby.h>
#include <SDL3/SDL.h>
/* Declarations only: this file has no main for SDL_main.h to rename. */
#define SDL_MAIN_HANDLED
#include <SDL3/SDL_main.h>

#include <pthread.h>
#include <unistd.h>

#ifdef __ANDROID__
#include <sys/syscall.h>
#endif

#ifdef __APPLE__
/*
 * Branch-only canary (iphone-canary): UIKit's and Core Animation's own
 * sizes, read through the Objective-C runtime so that this file stays C.
 * On arm64 objc_msgSend returns these structs of doubles in registers, so
 * one cast serves every message; a message to nil answers zeros.
 */
#include <objc/message.h>
#include <objc/runtime.h>

struct canary_size { double width, height; };
struct canary_rect { double x, y, width, height; };

static void *
canary_object(void *object, const char *selector)
{
    return object ? ((void *(*)(void *, SEL))objc_msgSend)(object, sel_registerName(selector)) : NULL;
}

static double
canary_double(void *object, const char *selector)
{
    return object ? ((double (*)(void *, SEL))objc_msgSend)(object, sel_registerName(selector)) : 0.0;
}

static struct canary_size
canary_size(void *object, const char *selector)
{
    struct canary_size none = {0, 0};
    return object ? ((struct canary_size (*)(void *, SEL))objc_msgSend)(object, sel_registerName(selector)) : none;
}

static struct canary_rect
canary_rect(void *object, const char *selector)
{
    struct canary_rect none = {0, 0, 0, 0};
    return object ? ((struct canary_rect (*)(void *, SEL))objc_msgSend)(object, sel_registerName(selector)) : none;
}

/* Appends UIKit's screen and window, and the renderer's CAMetalLayer. */
static void
canary_apple(SDL_Window *sdl_window, SDL_Renderer *renderer, VALUE line)
{
    void *window = SDL_GetPointerProperty(SDL_GetWindowProperties(sdl_window), SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL);
    void *screen = canary_object(window, "screen");
    void *layer = SDL_GetRenderMetalLayer(renderer);
    void *superlayer = canary_object(layer, "superlayer");
    struct canary_rect window_bounds = canary_rect(window, "bounds");
    struct canary_rect native_bounds = canary_rect(screen, "nativeBounds");
    struct canary_rect layer_frame = canary_rect(layer, "frame");
    struct canary_rect layer_bounds = canary_rect(layer, "bounds");
    struct canary_rect super_bounds = canary_rect(superlayer, "bounds");
    struct canary_size drawable = canary_size(layer, "drawableSize");
    double contents_scale = canary_double(layer, "contentsScale");

    rb_str_catf(line, " | UIScreen scale %.3f nativeScale %.3f nativeBounds %.0fx%.0f | UIWindow bounds %.2fx%.2f pt",
                canary_double(screen, "scale"), canary_double(screen, "nativeScale"), native_bounds.width, native_bounds.height,
                window_bounds.width, window_bounds.height);
    rb_str_catf(line, " | CAMetalLayer frame (%.2f,%.2f %.2fx%.2f) pt in superlayer %.2fx%.2f pt, contentsScale %.3f,"
                      " bounds*scale %.2fx%.2f px, drawableSize %.0fx%.0f px",
                layer_frame.x, layer_frame.y, layer_frame.width, layer_frame.height, super_bounds.width, super_bounds.height,
                contents_scale, layer_bounds.width * contents_scale, layer_bounds.height * contents_scale, drawable.width, drawable.height);
}
#endif

/* Everything one run of the loop holds, for its ensure. */
struct game {
    SDL_Window *window;
    SDL_Renderer *renderer;
    double seconds;
    long frames;
};

static VALUE symbol_down, symbol_move;

/* The calling thread's stack size in bytes, and whether it is the main thread. */
static VALUE
stack(VALUE self)
{
    size_t size = 0;
    int main_thread = 0;
#ifdef __APPLE__
    size = pthread_get_stacksize_np(pthread_self());
    main_thread = pthread_main_np();
#else
    pthread_attr_t attributes;
    if (pthread_getattr_np(pthread_self(), &attributes) == 0) {
        pthread_attr_getstacksize(&attributes, &size);
        pthread_attr_destroy(&attributes);
    }
    main_thread = getpid() == (pid_t)syscall(SYS_gettid);
#endif
    return rb_ary_new_from_args(2, SIZET2NUM(size), main_thread ? Qtrue : Qfalse);
}

/* Reads the block's answer, [red, green, blue, x, y], and draws the frame. */
static void
draw(struct game *game, VALUE answer, int width, int height)
{
    Check_Type(answer, T_ARRAY);
    if (RARRAY_LEN(answer) != 5) rb_raise(rb_eArgError, "the block answered %ld values, not [red, green, blue, x, y]", RARRAY_LEN(answer));
    float side = (float)(width < height ? width : height) / 6.0f;
    float x = (float)NUM2DBL(rb_ary_entry(answer, 3));
    float y = (float)NUM2DBL(rb_ary_entry(answer, 4));
    SDL_FRect square = {x - side / 2.0f, y - side / 2.0f, side, side};

    SDL_SetRenderDrawColor(game->renderer, (Uint8)NUM2INT(rb_ary_entry(answer, 0)), (Uint8)NUM2INT(rb_ary_entry(answer, 1)),
                           (Uint8)NUM2INT(rb_ary_entry(answer, 2)), SDL_ALPHA_OPAQUE);
    SDL_RenderClear(game->renderer);
    SDL_SetRenderDrawColor(game->renderer, 255, 255, 255, SDL_ALPHA_OPAQUE);
    SDL_RenderFillRect(game->renderer, &square);

    /*
     * Branch-only canary (iphone-canary): one-pixel edges, in the render
     * output's pixels, so that a column the drawable does not cover shows
     * as something other than the green background, and an edge that is
     * drawn but falls off the screen is missing its red or blue line.
     * Blue at the left (x = 0) and top (y = 0); red at the right
     * (x = width - 1) and bottom (y = height - 1).
     */
    SDL_FRect left = {0.0f, 0.0f, 1.0f, (float)height};
    SDL_FRect top = {0.0f, 0.0f, (float)width, 1.0f};
    SDL_FRect right = {(float)(width - 1), 0.0f, 1.0f, (float)height};
    SDL_FRect bottom = {0.0f, (float)(height - 1), (float)width, 1.0f};
    SDL_SetRenderDrawColor(game->renderer, 0, 0, 255, SDL_ALPHA_OPAQUE);
    SDL_RenderFillRect(game->renderer, &left);
    SDL_RenderFillRect(game->renderer, &top);
    SDL_SetRenderDrawColor(game->renderer, 255, 0, 0, SDL_ALPHA_OPAQUE);
    SDL_RenderFillRect(game->renderer, &right);
    SDL_RenderFillRect(game->renderer, &bottom);
    SDL_RenderPresent(game->renderer);
}

/*
 * Branch-only canary (iphone-canary): every size SDL, UIKit, and the
 * Metal layer report for the window, on one line. The loop prints it
 * whenever it changes, which is once per orientation change once the
 * rotation settles.
 */
static VALUE
canary_line(struct game *game)
{
    int points_w = 0, points_h = 0, pixels_w = 0, pixels_h = 0, output_w = 0, output_h = 0;
    SDL_Rect safe = {0, 0, 0, 0}, viewport = {0, 0, 0, 0};
    SDL_DisplayID display = SDL_GetDisplayForWindow(game->window);
    const SDL_DisplayMode *mode = SDL_GetCurrentDisplayMode(display);
    static const char *orientations[] = {"unknown", "landscape", "landscape-flipped", "portrait", "portrait-flipped"};
    SDL_DisplayOrientation orientation = SDL_GetCurrentDisplayOrientation(display);

    SDL_GetWindowSize(game->window, &points_w, &points_h);
    SDL_GetWindowSizeInPixels(game->window, &pixels_w, &pixels_h);
    SDL_GetCurrentRenderOutputSize(game->renderer, &output_w, &output_h);
    SDL_GetWindowSafeArea(game->window, &safe);
    SDL_GetRenderViewport(game->renderer, &viewport);

    VALUE line = rb_sprintf("SdlDemo canary: orientation %s | window %dx%d pt, %dx%d px, pixel density %.3f, display scale %.3f,"
                            " display content scale %.3f | render output %dx%d px, viewport (%d,%d %dx%d) | safe area (%d,%d %dx%d) pt",
                            (unsigned)orientation < 5 ? orientations[orientation] : "?", points_w, points_h, pixels_w, pixels_h,
                            SDL_GetWindowPixelDensity(game->window), SDL_GetWindowDisplayScale(game->window),
                            SDL_GetDisplayContentScale(display), output_w, output_h, viewport.x, viewport.y, viewport.w, viewport.h,
                            safe.x, safe.y, safe.w, safe.h);
    if (mode) rb_str_catf(line, " | display mode %dx%d pt, pixel density %.3f", mode->w, mode->h, mode->pixel_density);
#ifdef __APPLE__
    canary_apple(game->window, game->renderer, line);
#endif
    return line;
}

/* The loop: events, the block, a frame, until the time is up or SDL quits. */
static VALUE
loop(VALUE data)
{
    struct game *game = (struct game *)data;
    Uint64 end = SDL_GetTicks() + (Uint64)(game->seconds * 1000.0);
    int quit = 0;
    VALUE canary_last = Qnil;

    while (!quit && SDL_GetTicks() < end) {
        int width = 0, height = 0;
        SDL_GetCurrentRenderOutputSize(game->renderer, &width, &height);
        VALUE canary = canary_line(game);
        if (NIL_P(canary_last) || !RTEST(rb_str_equal(canary, canary_last))) {
            rb_io_puts(1, &canary, rb_stdout);
            canary_last = canary;
        }
        VALUE touches = rb_ary_new();
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) quit = 1;
            if (event.type == SDL_EVENT_FINGER_DOWN || event.type == SDL_EVENT_FINGER_MOTION) {
                VALUE kind = event.type == SDL_EVENT_FINGER_DOWN ? symbol_down : symbol_move;
                rb_ary_push(touches, rb_ary_new_from_args(3, DBL2NUM(event.tfinger.x * width), DBL2NUM(event.tfinger.y * height), kind));
            }
        }
        VALUE answer = rb_yield_values(4, LONG2NUM(game->frames), INT2NUM(width), INT2NUM(height), touches);
        if (answer == Qnil) break;
        draw(game, answer, width, height);
        game->frames++;
    }
    return LONG2NUM(game->frames);
}

static VALUE
close_game(VALUE data)
{
    struct game *game = (struct game *)data;
    if (game->renderer) SDL_DestroyRenderer(game->renderer);
    if (game->window) SDL_DestroyWindow(game->window);
    SDL_QuitSubSystem(SDL_INIT_VIDEO);
    return Qnil;
}

/*
 * SdlDemo.run(seconds) { |frame, width, height, touches| [red, green, blue, x, y] }
 *
 * Runs the frame loop for up to seconds, or until the block answers nil,
 * and returns how many frames it drew. Each touch is [x, y, :down] or
 * [x, y, :move], in the window's pixels.
 */
static VALUE
run(VALUE self, VALUE seconds)
{
    struct game game = {NULL, NULL, NUM2DBL(seconds), 0};

    rb_need_block();
    if (!SDL_Init(SDL_INIT_VIDEO)) rb_raise(rb_eRuntimeError, "SDL_Init: %s", SDL_GetError());
    if (!SDL_CreateWindowAndRenderer("SdlDemo", 0, 0, SDL_WINDOW_FULLSCREEN | SDL_WINDOW_HIGH_PIXEL_DENSITY, &game.window, &game.renderer)) {
        VALUE message = rb_sprintf("SDL_CreateWindowAndRenderer: %s", SDL_GetError());
        close_game((VALUE)&game);
        rb_exc_raise(rb_exc_new_str(rb_eRuntimeError, message));
    }
    SDL_SetRenderVSync(game.renderer, 1);
    return rb_ensure(loop, (VALUE)&game, close_game, (VALUE)&game);
}

/* SdlDemo.sdl_version: the version of the SDL the app links, such as "3.4.18". */
static VALUE
version(VALUE self)
{
    int linked = SDL_GetVersion();
    return rb_sprintf("%d.%d.%d", SDL_VERSIONNUM_MAJOR(linked), SDL_VERSIONNUM_MINOR(linked), SDL_VERSIONNUM_MICRO(linked));
}

/*
 * SdlDemo.claim_main_thread: tells SDL that the calling thread is its
 * main thread, as SDL_RunApp would (SDL_SetMainReady). ADR 025 tried it
 * on Ruby's own thread, under a host that runs UIKit on another.
 */
static VALUE
claim_main_thread(VALUE self)
{
    SDL_SetMainReady();
    return Qnil;
}

void
Init_sdl_demo(void)
{
    VALUE demo = rb_define_module("SdlDemo");
    symbol_down = ID2SYM(rb_intern("down"));
    symbol_move = ID2SYM(rb_intern("move"));
    rb_define_singleton_method(demo, "run", run, 1);
    rb_define_singleton_method(demo, "stack", stack, 0);
    rb_define_singleton_method(demo, "sdl_version", version, 0);
    rb_define_singleton_method(demo, "claim_main_thread", claim_main_thread, 0);
}
