module Consular
  module ITermDSL

    # Generates a pane in the terminal. Panes are split vertically by default,
    # but can also be split horizontally. Panes can be nested.
    #
    # @param [Array<String>] args
    #   Array of comamnds, first element can be a symbol specifying the
    #   direction of the pane split
    # @param [Proc] block
    #   Block of code to execute in pane context.
    #
    # @example
    #
    #   pane "top"
    #   pane { pane "uptime" }
    #   pane :horizontal, "iostat"
    #   pane :vertical, "df"
    #
    # @api public
    def pane(*args, &block)
      @_context[:panes] ||= []

      split_direction = args.shift if args.first.is_a? Symbol

      if block_given?
        @_context[:panes] << {:commands => [], :split_direction => split_direction}

        _context = @_context.clone
        run_context @_context[:panes].last, &block
        @_context = _context

      else
        @_context[:panes] << {:commands => args, :split_direction => split_direction}
      end
    end

  end
end

Consular::DSL.class_eval { include Consular::ITermDSL }
