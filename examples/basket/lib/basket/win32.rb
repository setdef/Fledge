# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

require "fiddle"

module Basket
  # Ruby's way to Win32's windows and common controls, with nothing but
  # Fiddle, which Ruby bundles. It is only as much as Basket's screen
  # calls, and it runs under any Ruby on Windows: user32 makes the window
  # and its buttons and text field, comctl32 the list, and the window
  # procedure is a Fiddle::Closure.
  #
  #   Win32.prepare(manifest)
  #   window = Win32::Window.open("Basket", width: 520, height: 420, default_button: 101)
  #   field = Win32::Edit.new(window, cue: "Add an item")
  #   window.on_command(101) { puts field.text }
  #   window.show
  #   Win32.run(window)
  #
  # Windows draws every control with the classic look unless the process
  # has asked for Common Controls 6, which a program's manifest asks for
  # and Ruby's executables have none of, so +prepare+ asks for it with
  # an activation context made from a manifest file. It also makes the
  # process aware of each monitor's scale, which Windows otherwise
  # answers by stretching the window's pixels.
  module Win32
    # What Windows' functions take and give, in Fiddle's type codes:
    # a handle, a WPARAM, an LPARAM, and an LRESULT are as wide as a
    # pointer, and a LONG is 32 bits, since Windows' integers are LLP64.
    module Types
      # A pointer.
      POINTER = Fiddle::TYPE_VOIDP
      # A handle, an LPARAM, or an LRESULT.
      HANDLE = Fiddle::TYPE_INTPTR_T
      # A WPARAM.
      WORD = Fiddle::TYPE_UINTPTR_T
      # An int.
      INT = Fiddle::TYPE_INT
      # A UINT or a DWORD.
      UINT = -Fiddle::TYPE_INT
      # A function that gives nothing back.
      VOID = Fiddle::TYPE_VOID
    end

    # The C functions the bridge calls.
    module Functions
      include Types

      # The C function +name+ of the library +file+, which Ruby calls
      # holding its lock, since a window procedure may call Ruby back.
      def self.function(file, name, args, ret)
        Fiddle::Function.new(Fiddle::Handle.new(file)[name], args, ret, need_gvl: true)
      end

      # The module of the running program, which a window is made in.
      MODULE_HANDLE = function("kernel32.dll", "GetModuleHandleW", [POINTER], HANDLE)
      # A manifest file made into an activation context.
      CREATE_ACTIVATION_CONTEXT = function("kernel32.dll", "CreateActCtxW", [POINTER], HANDLE)
      # Makes an activation context the thread's.
      ACTIVATE_CONTEXT = function("kernel32.dll", "ActivateActCtx", [HANDLE, POINTER], INT)
      # Makes every window of the process aware of its monitor's scale.
      SET_DPI_AWARENESS = function("user32.dll", "SetProcessDpiAwarenessContext", [HANDLE], INT)
      # The scale of the monitor a window is on, in dots per inch.
      WINDOW_DPI = function("user32.dll", "GetDpiForWindow", [HANDLE], UINT)
      # The path of the file the process runs from, into a buffer.
      MODULE_FILE_NAME = function("kernel32.dll", "GetModuleFileNameW", [HANDLE, POINTER, UINT], UINT)
      # A system metric at a scale.
      METRIC_FOR_DPI = function("user32.dll", "GetSystemMetricsForDpi", [INT, UINT], INT)
      # The large and the small icon of an icon group in a file, at the
      # sizes asked for: the large in the low word of the last argument,
      # the small in its high word.
      EXTRACT_ICON = function("shell32.dll", "SHDefExtractIconW", [POINTER, INT, UINT, POINTER, POINTER, UINT], INT)
      # The scale of the primary monitor.
      SYSTEM_DPI = function("user32.dll", "GetDpiForSystem", [], UINT)
      # A system setting at a scale.
      SYSTEM_PARAMETERS = function("user32.dll", "SystemParametersInfoForDpi", [UINT, UINT, POINTER, UINT, UINT], INT)
      # A font made from a LOGFONTW.
      CREATE_FONT = function("gdi32.dll", "CreateFontIndirectW", [POINTER], HANDLE)
      # The mouse pointer of a system's name.
      LOAD_CURSOR = function("user32.dll", "LoadCursorW", [HANDLE, HANDLE], HANDLE)
      # Registers a window class.
      REGISTER_CLASS = function("user32.dll", "RegisterClassExW", [POINTER], -Fiddle::TYPE_SHORT)
      # Makes a window, or a control, which is a window of a class
      # Windows defines.
      CREATE_WINDOW = function("user32.dll", "CreateWindowExW",
        [UINT, POINTER, POINTER, UINT, INT, INT, INT, INT, HANDLE, HANDLE, HANDLE, HANDLE], HANDLE)
      # What a window does with a message it has no use for.
      DEFAULT_PROCEDURE = function("user32.dll", "DefWindowProcW", [HANDLE, UINT, WORD, HANDLE], HANDLE)
      # Sends a message and waits for the answer.
      SEND_MESSAGE = function("user32.dll", "SendMessageW", [HANDLE, UINT, WORD, HANDLE], HANDLE)
      # Puts a message in the queue of the window's thread.
      POST_MESSAGE = function("user32.dll", "PostMessageW", [HANDLE, UINT, WORD, HANDLE], INT)
      # The next message of the thread's queue, waiting for one.
      GET_MESSAGE = function("user32.dll", "GetMessageW", [POINTER, HANDLE, UINT, UINT], INT)
      # Gives Tab and Return their meaning in a window of controls.
      DIALOG_MESSAGE = function("user32.dll", "IsDialogMessageW", [HANDLE, POINTER], INT)
      # Turns key presses into characters.
      TRANSLATE_MESSAGE = function("user32.dll", "TranslateMessage", [POINTER], INT)
      # Sends a message to the window procedure of the window it is for.
      DISPATCH_MESSAGE = function("user32.dll", "DispatchMessageW", [POINTER], HANDLE)
      # Ends the message loop.
      POST_QUIT = function("user32.dll", "PostQuitMessage", [INT], VOID)
      # Shows a window.
      SHOW_WINDOW = function("user32.dll", "ShowWindow", [HANDLE, INT], INT)
      # The size of a window's inside, as a RECT.
      CLIENT_RECT = function("user32.dll", "GetClientRect", [HANDLE, POINTER], INT)
      # Places a window within its parent.
      MOVE_WINDOW = function("user32.dll", "MoveWindow", [HANDLE, INT, INT, INT, INT, INT], INT)
      # Gives a window the keyboard.
      SET_FOCUS = function("user32.dll", "SetFocus", [HANDLE], HANDLE)
      # The length of a window's text, in characters.
      TEXT_LENGTH = function("user32.dll", "GetWindowTextLengthW", [HANDLE], INT)
      # A window's text.
      GET_TEXT = function("user32.dll", "GetWindowTextW", [HANDLE, POINTER, INT], INT)
      # Sets a window's text.
      SET_TEXT = function("user32.dll", "SetWindowTextW", [HANDLE, POINTER], INT)
    end

    # Raised when a call to Windows fails.
    class Error < StandardError; end

    # A buffer of +size+ zeroed bytes, whose address Windows is given.
    def self.buffer(size)
      Fiddle::Pointer.malloc(size, Fiddle::RUBY_FREE).tap { |pointer| pointer[0, size] = "\0".b * size }
    end

    # +text+ as the zero-ended UTF-16 a wide function takes.
    def self.wide(text)
      bytes = "#{text}\0".encode(Encoding::UTF_16LE).b
      buffer(bytes.bytesize).tap { |pointer| pointer[0, bytes.bytesize] = bytes }
    end

    # The +characters+ UTF-16 characters at +pointer+, as a String.
    def self.string(pointer, characters)
      pointer[0, 2 * characters].force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8)
    end

    # The path of the program the process runs, which is where its icon
    # is: Explorer and the taskbar show the first icon group of that file.
    def self.program_path
      path = buffer(2 * 32_768)
      string(path, Functions::MODULE_FILE_NAME.call(0, path, 32_768))
    end

    # The system's message font at +dpi+, a handle, which the controls
    # of a window take as their font.
    def self.message_font(dpi)
      @fonts ||= {}
      @fonts[dpi] ||= begin
        metrics = buffer(504)
        metrics[0, 4] = [504].pack("L")
        # SPI_GETNONCLIENTMETRICS, whose lfMessageFont is at byte 408.
        Functions::SYSTEM_PARAMETERS.call(0x29, 504, metrics, 0, dpi).zero? and raise Error, "Windows gave no message font"
        Functions::CREATE_FONT.call(metrics + 408)
      end
    end

    # Asks Windows for each monitor's scale, and for Common Controls 6,
    # as the manifest file at +path+ says it. A process asks once, and
    # before it makes a window.
    def self.prepare(path)
      return if @prepared

      # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2; Windows older than
      # 10 version 1703 refuse, and the window is then scaled as before.
      Functions::SET_DPI_AWARENESS.call(-4)
      context = Functions::CREATE_ACTIVATION_CONTEXT.call(activation(path))
      context == -1 and raise Error, "Windows did not read #{path}: error #{Fiddle.win32_last_error}"
      Functions::ACTIVATE_CONTEXT.call(context, buffer(8)).zero? and raise Error, "Windows did not activate #{path}"
      start_common_controls
      @prepared = true
    end

    # An ACTCTXW of the manifest at +path+.
    private_class_method def self.activation(path)
      @manifest = wide(path.tr("/", "\\"))
      buffer(56).tap { |context| context[0, 16] = [56, 0, @manifest.to_i].pack("LLQ") }
    end

    # Loads comctl32 under the activation context, which gives the
    # process its version 6, and starts its list.
    private_class_method def self.start_common_controls
      start = Fiddle::Function.new(Fiddle::Handle.new("comctl32.dll")["InitCommonControlsEx"], [Types::POINTER], Types::INT)
      classes = buffer(8)
      # ICC_LISTVIEW_CLASSES | ICC_STANDARD_CLASSES
      classes[0, 8] = [8, 0x1 | 0x4000].pack("LL")
      start.call(classes).zero? and raise Error, "Windows did not start Common Controls 6"
    end

    # Handles the messages of +window+'s thread until its window is
    # closed. Tab and Return then work as in a dialog: Return presses
    # the window's default button.
    def self.run(window)
      message = buffer(48)
      while Functions::GET_MESSAGE.call(message, 0, 0, 0) > 0
        next unless Functions::DIALOG_MESSAGE.call(window.handle, message).zero?

        Functions::TRANSLATE_MESSAGE.call(message)
        Functions::DISPATCH_MESSAGE.call(message)
      end
    end

    # A top-level window, and what its messages do. A message nobody
    # asked about gets Windows' default answer.
    class Window
      include Types

      # WM_DESTROY
      DESTROY = 0x02
      # WM_SIZE
      SIZE = 0x05
      # WM_COMMAND
      COMMAND = 0x111
      # WM_NOTIFY
      NOTIFY = 0x4E
      # DM_GETDEFID, which Return asks the window to find its default button.
      GET_DEFAULT_ID = 0x400
      # LVN_KEYDOWN, a list's notification of a key press.
      KEY_DOWN = 0xFFFFFF65

      # The windows of the process, by handle.
      WINDOWS = {}

      # One procedure for every window, which finds the window and asks it.
      PROCEDURE = Fiddle::Closure::BlockCaller.new(HANDLE, [HANDLE, UINT, WORD, HANDLE]) do |handle, message, word, long|
        window = WINDOWS[handle]
        window ? window.receive(message, word, long) : Functions::DEFAULT_PROCEDURE.call(handle, message, word, long)
      end

      # The window's handle.
      attr_reader :handle

      # The window's scale, in dots per inch.
      attr_reader :dpi

      # A window titled +title+, of +width+ by +height+ pixels at 96
      # dots per inch, and more on a monitor of more, whose default
      # button is the control of the id +default_button+.
      def self.open(title, width:, height:, default_button:)
        instance = Functions::MODULE_HANDLE.call(nil)
        name = Win32.wide("BasketWindow")
        register(name, instance)
        scale = Functions::SYSTEM_DPI.call / 96.0
        # WS_OVERLAPPEDWINDOW, and CW_USEDEFAULT where the window goes.
        handle = Functions::CREATE_WINDOW.call(0, name, Win32.wide(title), 0x00CF0000, -0x80000000, -0x80000000,
          (width * scale).round, (height * scale).round, 0, 0, instance, 0)
        handle.zero? and raise Error, "Windows made no window: error #{Fiddle.win32_last_error}"
        new(handle, default_button).tap do |window|
          WINDOWS[handle] = window
          window.use_program_icon
        end
      end

      # Registers the class of the windows of this procedure, as a
      # WNDCLASSEXW says it: its size, CS_HREDRAW | CS_VREDRAW, the
      # procedure, two byte counts, the module, an icon, the system's
      # arrow, COLOR_WINDOW + 1 for the background, a menu, the class's
      # name, and a second icon.
      private_class_method def self.register(name, instance)
        arrow = Functions::LOAD_CURSOR.call(0, 32512)
        class_data = Win32.buffer(80)
        class_data[0, 80] = [80, 3, PROCEDURE.to_i, 0, 0, instance, 0, arrow, 6, 0, name.to_i, 0].pack("LLQllQQQQQQQ")
        Functions::REGISTER_CLASS.call(class_data)
      end

      # The window of +handle+, whose Return presses the button of the id +default_button+.
      def initialize(handle, default_button)
        @handle = handle
        @default_button = default_button
        @dpi = Functions::WINDOW_DPI.call(handle)
        @commands = {}
        @keys = {}
      end

      # Calls the block with the window's width and height in pixels,
      # now and whenever the window is sized.
      def on_size(&block)
        @size = block
        rectangle = Win32.buffer(16)
        Functions::CLIENT_RECT.call(@handle, rectangle)
        _left, _top, width, height = rectangle[0, 16].unpack("l4")
        block.call(width, height)
      end

      # Calls the block when the button of the id +id+ is pressed, with
      # the mouse, or with Return if it is the default.
      def on_command(id, &block)
        @commands[id] = block
      end

      # Calls the block with the virtual-key code of each key pressed in
      # +list+, a ListView.
      def on_key_down(list, &block)
        @keys[list.handle] = block
      end

      # Gives the window the first icon of the program it runs, as WM_SETICON
      # does for the title bar (small) and the taskbar and Alt-Tab (large),
      # at the sizes this window's scale gives them (SM_CXSMICON and
      # SM_CXICON). A window class with no icon, which this one has, and a
      # window that sets none show the generic application icon, whatever
      # icon the program's file holds.
      def use_program_icon
        large = Functions::METRIC_FOR_DPI.call(11, @dpi)
        small = Functions::METRIC_FOR_DPI.call(49, @dpi)
        icons = Win32.buffer(16)
        found = Functions::EXTRACT_ICON.call(Win32.wide(Win32.program_path), 0, 0, icons, icons + 8, (small << 16) | large)
        return unless found.zero?

        big, little = icons[0, 16].unpack("QQ")
        # WM_SETICON, ICON_SMALL then ICON_BIG.
        Functions::SEND_MESSAGE.call(@handle, 0x80, 0, little)
        Functions::SEND_MESSAGE.call(@handle, 0x80, 1, big)
      end

      # +pixels+ at 96 dots per inch, at this window's scale.
      def scale(pixels)
        (pixels * @dpi / 96.0).round
      end

      # Shows the window.
      def show
        Functions::SHOW_WINDOW.call(@handle, 5)
      end

      # Asks the window to close, as its close button does, which ends
      # Win32.run.
      def close
        Functions::POST_MESSAGE.call(@handle, 0x10, 0, 0)
      end

      # What the window procedure does with a message of this window.
      def receive(message, word, long)
        case message
        when SIZE
          @size&.call(long & 0xFFFF, (long >> 16) & 0xFFFF)
          0
        when COMMAND
          command(word, long)
        when NOTIFY
          key_down(long) || default(message, word, long)
        when GET_DEFAULT_ID
          # DC_HASDEFID in the high word, and the button's id in the low.
          (0x534B << 16) | @default_button
        when DESTROY
          WINDOWS.delete(@handle)
          Functions::POST_QUIT.call(0)
          0
        else
          default(message, word, long)
        end
      end

      private def default(message, word, long)
        Functions::DEFAULT_PROCEDURE.call(@handle, message, word, long)
      end

      # A pressed button: BN_CLICKED, notification code 0, in the high word.
      private def command(word, long)
        block = @commands[word & 0xFFFF]
        return default(COMMAND, word, long) unless block && ((word >> 16) & 0xFFFF).zero?

        block.call
        0
      end

      # An NMHDR, which a notification begins with, is the control's
      # handle, its id, and the code; an NMLVKEYDOWN goes on with the key.
      private def key_down(long)
        header = Fiddle::Pointer.new(long)
        block = @keys[header[0, 8].unpack1("q")]
        return unless block && header[16, 4].unpack1("L") == KEY_DOWN

        block.call(header[24, 2].unpack1("S"))
        0
      end
    end

    # A control, a child window of a class that Windows defines.
    class Control
      # The control's handle.
      attr_reader :handle

      # A control of the class +kind+ in +window+, with +text+, the
      # +style+ and +extended+ style bits it asks for beyond a visible
      # child that Tab reaches, and the id that +window+ hears its
      # commands by.
      def initialize(window, kind, text: "", style: 0, extended: 0, id: 0)
        # WS_CHILD | WS_VISIBLE | WS_TABSTOP
        @handle = Functions::CREATE_WINDOW.call(extended, Win32.wide(kind), Win32.wide(text), 0x50010000 | style,
          0, 0, 0, 0, window.handle, id, Functions::MODULE_HANDLE.call(nil), 0)
        @handle.zero? and raise Error, "Windows made no #{kind}: error #{Fiddle.win32_last_error}"
        # WM_SETFONT, with the system's message font.
        send_message(0x30, Win32.message_font(window.dpi), 1)
      end

      # Places the control at +x+, +y+, of +width+ by +height+ pixels, in its window.
      def move(x, y, width, height)
        Functions::MOVE_WINDOW.call(@handle, x, y, width, height, 1)
      end

      # Gives the control the keyboard.
      def focus
        Functions::SET_FOCUS.call(@handle)
      end

      # The control's text.
      def text
        length = Functions::TEXT_LENGTH.call(@handle)
        buffer = Win32.buffer(2 * (length + 1))
        Win32.string(buffer, Functions::GET_TEXT.call(@handle, buffer, length + 1))
      end

      # Sets the control's text.
      def text=(text)
        Functions::SET_TEXT.call(@handle, Win32.wide(text))
      end

      # Sends the control a message, and returns its answer.
      def send_message(message, word = 0, long = 0)
        Functions::SEND_MESSAGE.call(@handle, message, word, long)
      end
    end

    # A single-line text field.
    class Edit < Control
      # A field in +window+ that shows +cue+ while it is empty, which
      # only Common Controls 6 draws.
      def initialize(window, cue: "")
        # WS_EX_CLIENTEDGE, and ES_AUTOHSCROLL.
        super(window, "EDIT", style: 0x80, extended: 0x200)
        shown = Win32.wide(cue)
        # EM_SETCUEBANNER, with the cue shown while the field has focus too.
        send_message(0x1501, 1, shown.to_i)
      end
    end

    # A push button.
    class Button < Control
      # A button in +window+ that says +label+, and is the window's
      # default button when +default+.
      def initialize(window, label, id:, default: false)
        # BS_DEFPUSHBUTTON
        super(window, "BUTTON", text: label, style: default ? 1 : 0, id:)
      end
    end

    # A list of one column of items, one to a row, of which one can be
    # selected.
    class ListView < Control
      # LVM_GETITEMCOUNT
      COUNT = 0x1004
      # LVM_DELETEITEM
      DELETE = 0x1008
      # LVM_GETNEXTITEM
      NEXT = 0x100C
      # LVM_SETITEMSTATE
      STATE = 0x102B
      # LVM_INSERTITEMW
      INSERT = 0x104D
      # LVM_INSERTCOLUMNW
      COLUMN = 0x1061
      # LVM_SETCOLUMNWIDTH
      COLUMN_WIDTH = 0x101E

      # A list in +window+.
      def initialize(window)
        # WS_EX_CLIENTEDGE; LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS |
        # LVS_NOCOLUMNHEADER.
        super(window, "SysListView32", style: 0x400D, extended: 0x200)
        column = Win32.buffer(56)
        # LVCF_FMT | LVCF_WIDTH
        column[0, 12] = [0x3, 0, 100].pack("Lll")
        send_message(COLUMN, 0, column.to_i)
        # LVM_SETEXTENDEDLISTVIEWSTYLE: LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER.
        send_message(0x1036, 0x10020, 0x10020)
      end

      # How many rows the list has.
      def count
        send_message(COUNT)
      end

      # Adds a row of +text+ at the end.
      def add(text)
        item = Win32.buffer(88)
        shown = Win32.wide(text)
        # LVIF_TEXT, the row, the column, and the text's address.
        item[0, 12] = [0x1, count, 0].pack("Lll")
        item[24, 8] = [shown.to_i].pack("Q")
        send_message(INSERT, 0, item.to_i)
        fit_column
      end

      # Takes the row at +index+ away.
      def remove(index)
        send_message(DELETE, index)
        fit_column
      end

      # The index of the selected row, or nil.
      def selected
        # LVNI_SELECTED, searching from before row 0.
        index = send_message(NEXT, (-1) & 0xFFFFFFFFFFFFFFFF, 0x2)
        index unless index.negative?
      end

      # Selects the row at +index+, and gives it the focus rectangle.
      def select(index)
        item = Win32.buffer(88)
        # LVIS_FOCUSED | LVIS_SELECTED, as state and as mask.
        item[12, 8] = [0x3, 0x3].pack("LL")
        send_message(STATE, index, item.to_i)
      end

      # Makes the column as wide as the list's inside, which a vertical
      # scroll bar narrows, so that a selected row's highlight, which
      # spans its columns, reaches the list's edge. It is the list's
      # inside, not the window's width less a guess at the borders and
      # the scroll bar, that Windows lays the column in.
      def fit_column
        inside = Win32.buffer(16)
        Functions::CLIENT_RECT.call(@handle, inside)
        send_message(COLUMN_WIDTH, 0, inside[0, 16].unpack("l4")[2])
      end
    end
  end
end
