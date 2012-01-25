require 'consular'
require 'appscript'
require File.expand_path('../iterm_dsl', __FILE__)

module Consular

  # Consular Core to interact with iTerm2 for Mac OS X
  #
  class ITerm < Core
    include Appscript

    Consular.add_core self

    class << self

      # Checks to see if the current system is darwin and
      # if $TERM_PROGRAM is iTerm.app
      #
      # @api public
      def valid_system?
        (RUBY_PLATFORM.downcase =~ /darwin/) && ENV['TERM_PROGRAM'] == 'iTerm.app'
      end

      # Returns the name of Core. Used in CLI core selection.
      #
      # @api public
      def to_s
        "Consular::ITerm Mac OSX iTerm2"
      end

    end

    # Initializes a reference to the iTerm.app via appscript
    #
    # @param [String] path
    #   Path to Termfile
    #
    # @api public
    def initialize(path)
      super
      @terminal = app('iTerm')
    end

    # Method called by runner to Execute Termfile setup.
    #
    # @api public
    def setup!
      @termfile[:setup].each { |cmd| execute_command(cmd) }
    end

    # Method called by runner to execute Termfile.
    #
    # @api public
    def process!
      windows = @termfile[:windows]
      default = windows.delete('default')
      execute_window(default, :default => true) unless default[:tabs].empty?
      windows.each_pair { |_, cont| execute_window(cont) }
    end

    # Prepends the :before commands to the current context's
    # commands if it exists.
    #
    # @param [Array<String>] commands
    #   The current tab commands
    # @param [Array<String>] befores
    #   The current window's :befores
    #
    # @return [Array<String>]
    #   The current context commands with the :before commands prepended
    #
    # @api public
    def prepend_befores(commands, befores = nil)
      unless befores.nil? || befores.empty?
        commands.insert(0, befores).flatten!
      else
        commands
      end
    end

    # Prepend a title setting command prior to the other commands.
    #
    # @param [String] title
    #   The title to set for the context of the commands.
    # @param [Array<String>] commands
    #   The context of commands to preprend to.
    #
    # @api public
    def set_title(title, commands)
      cmd = "PS1=\"$PS1\\[\\e]2;#{title}\\a\\]\""
      title ? commands.insert(0, cmd) : commands
    end

    # Executes the commands for each designated window.
    # .run_windows will iterate through each of the tabs in
    # sorted order to execute the tabs in the order they were set.
    # The logic follows this:
    #
    #   If the content is for the 'default' window,
    #   then use the current active window and generate the commands.
    #
    #   If the content is for a new window,
    #   then generate a new window and activate the windows.
    #
    #   Otherwise, open a new tab and execute the commands.
    #
    # @param [Hash] content
    #   The hash contents of the window from the Termfile.
    # @param [Hash] options
    #   Addional options to pass. You can use:
    #     :default - Whether this is being run as the default window.
    #
    # @example
    #   @core.execute_window contents, :default => true
    #   @core.execute_window contents, :default => true
    #
    # @api public
    def execute_window(content, options = {})
      window_options = content[:options]
      first_run = true

      content[:tabs].each do |key,tab|
        _tab =
          if first_run && !options[:default]
            open_window options.merge(window_options)
          else
            open_tab(content[:options]) unless key == 'default'
            active_tab
          end

        first_run = false

        commands = prepend_befores tab[:commands], content[:before]
        commands = set_title options[:name], commands
        commands.each { |cmd| execute_command cmd, :in => _tab }

        execute_panes(tab) if tab.key? :panes
      end
    end

    # Execute the tab and associated panes with the designated content
    #
    # @param [Hash] content
    #   The Context containing panes.
    #
    # @api public
    def execute_panes(content)
      panes, commands = content.values_at :panes, :commands

      panes.each do |pane|
        execute_and_split_pane pane, commands, :no_split => (pane == panes.first)
      end

      panes.reverse.each_with_index do |pane,i|
        (pane[:panes] ||= [])
          .each{ |pane| execute_and_split_pane pane, commands }
          .length.times{ previous_pane }

        previous_pane unless pane == panes.first
      end
    end

    # Execute commands in the context of the pane and splits it by default
    # unless specified not to.
    #
    # @param [Array] pane
    #   Sub panes for the top level pane
    # @param [Array] tabc_ommands
    #   Tab commands
    # @param [Hash] options
    #   Options
    #
    # @api public
    def execute_and_split_pane(pane, tab_commands, options={})
      split pane[:split_direction] unless options[:no_split]
      execute_pane_commands pane[:commands], tab_commands
    end

    # Execute the commands within a pane
    #
    # @param [Array] pane_commands
    #   Commands for the designated pane.
    # @param [Array] tab_commands
    #   Commands for the designated tabs.
    #
    # @api public
    def execute_pane_commands(pane_commands=[], tab_commands=[])
      (tab_commands + pane_commands).each { |cmd| execute_command cmd }
    end

    # Split the active tab in the specified manner, defaults to vertical
    #
    # @param [Symbol] direction
    #   Direction to split the pane, should be :vertical or :horizontal
    #
    # @api public
    def split(direction)
      direction ||= :vertical
      call_ui_action "Shell", nil, "Split #{direction.to_sym}ly with Current Profile"
    end

    # to select panes; iTerm's Appscript select method does not work
    # as expected, we have to select via menu instead
    #
    # @param [String] direction
    #   Direction to split the pane. The valid directions are:
    #   'Above', 'Below', 'Left', 'Right'
    #
    # @api public
    def select_pane(direction)
      valid_directions = %w[Above Below Left Right]
      if valid_directions.include?(direction)
        call_ui_action("Window", "Select Split Pane", "Select Pane #{direction}")
      else
        puts "Error: #{direction} is not a valid direction to select a pane; Only Above/Below/Left/Right are valid directions"
      end
    end

    # Moves focuse back to the previous pane.
    #
    # @api public
    def previous_pane
      call_ui_action "Window", "Select Split Pane", "Previous Pane"
    end

    # Opens a new tab and focuses on it.
    #
    # @param [Hash] options
    #   Additional options to further customize the tab.
    #
    # @api public
    def open_tab(options = nil)
      active_window.launch_ :session => 'New session'
    end

    # Opens a new window and focuses
    # on the new tab.
    #
    # @param [Hash] options
    #   Additional options to further customize the window.
    #
    # @api public
    def open_window(options = nil)
      window = @terminal.make :new => :terminal
      window.launch_ :session => 'New session'
    end

    # Execute the given command in the context of the active window.
    #
    # @param [String] cmd
    #   The command to execute.
    # @param [Hash] options
    #   Additional options to pass into appscript for the context.
    #
    # @example
    #   @osx.execute_command 'ps aux', :in => @tab_object
    #
    # @api public
    def execute_command(cmd, options = {})
      context = options[:in] || active_tab
      context.write :text => cmd
    end

    # Returns the active tab e.g the active terminal session.
    #
    # @api public
    def active_tab
      active_window.current_session
    end

    # Returns the active window/tab e.g the active terminal window.
    #
    # @api public
    def active_window
      @terminal.current_terminal
    end

    # Returns a reference to the iTerm menu bar.
    #
    # @api public
    def iterm_menu
      _process = app("System Events").processes["iTerm"]
      _process.menu_bars.first
    end

    # Execute the menu action via UI.
    #
    # @param [String] menu
    #   Top level menu name
    # @param [String] submenu
    #   Sub level menu name
    # @param [String] action
    #   Action name/description.
    #
    # @example
    #   @core.call_ui_action 'Edit', 'Find', 'Find Next'
    #   @core.call_ui_action 'Shell', nil, 'Split Vertically With Same Profile'
    #
    # @api public
    def call_ui_action(menu, submenu, action)
      menu = iterm_menu.menu_bar_items[menu].menus[menu]
      menu = menu.menu_items[submenu].menus[submenu] if submenu
      menu.menu_items[action].click
    end

  end
end
