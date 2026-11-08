/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
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
    SDL_RenderPresent(game->renderer);
}

/* The loop: events, the block, a frame, until the time is up or SDL quits. */
static VALUE
loop(VALUE data)
{
    struct game *game = (struct game *)data;
    Uint64 end = SDL_GetTicks() + (Uint64)(game->seconds * 1000.0);
    int quit = 0;

    while (!quit && SDL_GetTicks() < end) {
        int width = 0, height = 0;
        SDL_GetCurrentRenderOutputSize(game->renderer, &width, &height);
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
