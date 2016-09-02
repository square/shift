require 'mysql-parser'

def short_run(state)
  state[:run][:short] = true;
end

def long_run(state)
  state[:run][:long] = true;
end

def nocheckalter_run(state)
  state[:run][:nocheckalter] = true;
end

def need_resolution(state)
  unless state[:run][:long] || state[:run][:short] || state[:run][:nocheckalter]
    raise ShiftInternalError, "Can't determine running type"
  end
end

class ShiftError < StandardError
end

class ShiftInternalError < StandardError
end

def require_default_when_not_null(tree)
  tree.find_all(name: :r_column_definition).each do |col_def|
    null = col_def.find_top(name: :r_opt_NULL_status)
    default = col_def.find_top(name: :r_opt_DEFAULT_with_val)

    if null.subname == :NOT_NULL && default.subname == :empty
      raise ShiftError, 'NOT NULL column needs a default value'
    end
  end
end

def check_enum_and_column_rename(state, checker, tree, name)
  # after long_run, we can quit the function, but after short_run,
  # we have to continue checking
  arr = tree.find_all(name: :r_alter_specification, subname: :MODIFY_col) +
        tree.find_all(name: :r_alter_specification, subname: :CHANGE_col)

  arr.each do |mod_tree|
    enum = mod_tree
      .find_top(name: :r_column_definition)
      .find_left(name: :r_datatype, subname: :ENUM)

    col_names = nil
    if mod_tree.subname == :CHANGE_col
      col_names = mod_tree.find_all(name: :r_col_name)
      # column name is being changed
      nocheckalter_run(state) if col_names[0].norm_name != col_names[1].norm_name
    end

    long_run(state) if enum.nil?

    if checker
      columns = checker.call(name)
      col_name = mod_tree.find_left(name: :r_col_name).norm_name
      props = columns[col_name]

      raise ShiftError, 'column not found' if props.nil?

      next if enum.nil?

      unless ['enum', 'varchar', 'set'].any? { |e| props[:type].start_with? e }
        raise ShiftError, "#{col_name} can't be converted to ENUM"
      end

      next if col_names && col_names[0].norm_name != col_names[1].norm_name

      old_enum = props[:type][5..-2] # remove "enum(" ... ")"
      comma_separated_string = enum.find_left(name: :r_comma_separated_string)
      if comma_separated_string.to_s.start_with? old_enum
        lst = comma_separated_string
          .to_list
          .select { |st| st.name == :string }
        if lst.length <= 255
          short_run(state)
        else
          long_run(state)
        end
      else
        long_run(state)
      end
    else
      # just to make it pass, we should always provide get_columns
      short_run(state)
    end
  end
end

class OscParser

  def extract_names(tree)
    arr = tree.find_all(name: :r_view_name) + tree.find_all(name: :r_tbl_name)
    arr.map { |t| t.norm_name }
  end

  def initialize
    @parser = MySQLParser.new
    @checkers = Hash.new

    state = {
      run: Hash.new,
      table_names: [],
      dropped_foreign_keys: [],
    }
    @parser.merge_state! state

    hooks = {
      # ===============================
      # ======== extract action =======
      # ===============================

      r_CREATE_VIEW: lambda do |tree, state|
        short_run(state);
        state[:action] = :create
        state[:mode] = :view
        state[:table_names] = extract_names(tree.find_top(name: :r_view_name))
        name = state[:table_names][0]
        exists = @checkers[:table_exists]
        if exists && exists.call(:view, name)
          raise ShiftError, "view already exists!"
        end
      end,

      r_CREATE_TABLE: lambda do |tree, state|
        short_run(state);
        state[:action] = :create
        state[:mode] = :table
        state[:table_names] = extract_names(tree.find_top(name: :r_tbl_name))
        name = state[:table_names][0]
        exists = @checkers[:table_exists]
        if exists && exists.call(:table, name)
          raise ShiftError, "table already exists!"
        end
      end,

      r_ALTER_TABLE: lambda do |tree, state|
        state[:action] = :alter
        state[:mode] = :table
        state[:table_names] = extract_names(tree.find_top(name: :r_tbl_name))
        name = state[:table_names][0]
        exists = @checkers[:table_exists]
        if exists && !exists.call(:table, name)
          raise ShiftError, "table does not exist!"
        end

        check_enum_and_column_rename(state, @checkers[:get_columns], tree, name)

        need_resolution(state)
      end,

      r_DROP_VIEW: lambda do |tree, state|
        short_run(state);
        state[:action] = :drop
        state[:mode] = :view
        state[:table_names] =
          extract_names(tree.find_top(name: :r_comma_separated_view_name))
        if state[:table_names].length > 1
          raise ShiftError, "dropping multiple views is not supported!"
        end
        exists = @checkers[:table_exists]
        name = state[:table_names][0]
        if exists && !exists.call(:view, name)
          raise ShiftError, "view does not exist!"
        end
      end,

      r_DROP_TABLE: lambda do |tree, state|
        short_run(state);
        state[:action] = :drop
        state[:mode] = :table
        state[:table_names] =
          extract_names(tree.find_top(name: :r_comma_separated_tbl_name))
        if state[:table_names].length > 1
          raise ShiftError, "dropping multiple tables is not supported!"
        end
        exists = @checkers[:table_exists]
        name = state[:table_names][0]
        if exists && !exists.call(:table, name)
          raise ShiftError, "table does not exist!"
        end
      end,

      # =====================
      # ======== body =======
      # =====================

      r_opt_alter_commands__empty: lambda do |tree, state|
        short_run(state);
      end,

      r_opt_alter_commands__single: lambda do |tree, state|
        long_run(state)
      end,

      r_charset_name: lambda do |tree, state|
        raise ShiftError, "charset #{tree} not supported."
      end,

      r_datatype__spatial: lambda do |tree, state|
        raise ShiftError, 'spatial type not supported'
      end,

      r_opt_PARTITION_options__REMOVE: lambda do |tree, state|
        long_run(state)
      end,

      r_opt_PARTITION_options__PARTITION: lambda do |tree, state|
        raise ShiftError, 'partition by not supported'
      end,

      r_shared_create_alter__SPATIAL: lambda do |tree, state|
        raise ShiftError, 'spatial not supported'
      end,

      r_shared_create_alter__FOREIGN_KEY: lambda do |tree, state|
        raise ShiftError, 'foreign key not supported'
      end,

      r_alter_specification__table_options: lambda do |tree, state|
        long_run(state)
      end,

      r_alter_specification__ADD_col: lambda do |tree, state|
        long_run(state)
        require_default_when_not_null(tree)
      end,

      r_alter_specification__ADD_cols: lambda do |tree, state|
        long_run(state)
        require_default_when_not_null(tree)
      end,

      r_alter_specification__ADD_shared: lambda do |tree, state|
        long_run(state)
      end,

      r_alter_specification__ALTER_col_SET_or_DROP_DEFAULT: lambda do |tree, state|
        long_run(state)
      end,

      r_alter_specification__DROP_col: lambda do |tree, state|
        long_run(state)
      end,

      r_alter_specification__DROP_FOREIGN_KEY: lambda do |tree, state|
        long_run(state)
        fk_symbol = tree.find_top(name: :r_fk_symbol)
        norm_name = fk_symbol.norm_name
        state[:dropped_foreign_keys] << norm_name
        ident = fk_symbol.find_top(name: :ident)
        raw_ident = ident.find_left(name: :raw_ident)

        if raw_ident
          norm_name[0] == "_" ?
            raw_ident.val[0] = norm_name[1..-1] :
            raw_ident.val[0] = "_" + norm_name
        else
          norm_name[0] == "_" ?
            ident.find_left(name: :opt_ident_in_backtick).val[1] = norm_name[1..-1] :
            ident.find_left(name: :opt_ident_in_backtick).val[1] = "_" + norm_name
        end
      end,

      r_alter_specification__DISABLE_KEYS: lambda do |tree, state|
        long_run(state)
      end,

      r_alter_specification__ENABLE_KEYS: lambda do |tree, state|
        long_run(state)
      end,

      r_alter_specification__RENAME: lambda do |tree, state|
        long_run(state)
      end,

      r_alter_specification__CONVERT: lambda do |tree, state|
        long_run(state)
      end,

      r_alter_specification__CHARACTER_SET_COLLATE: lambda do |tree, state|
        long_run(state)
      end,

      r_alter_specification__DROP_index: lambda do |tree, state|
        short_run(state)
      end,

      r_datatype__ENUM: lambda do |tree, state|
        to_remove_space = [
          tree.find_top(name: :left_paren),
          tree.find_top(name: :r_comma_separated_string)
        ]

        to_remove_space.each do |st|
          st.find_all(name: :S).each do |space|
            space.val[0] = ""
          end
        end
      end,

      r_alter_specification__DROP_PRIMARY_KEY: lambda do |tree, state|
        raise ShiftError, 'drop primary key not supported'
      end,

      r_opt_after_alter__ORDER_BY: lambda do |tree, state|
        raise ShiftError, 'order by not supported'
      end,

      r_data_directory_equal_with_val: lambda do |tree, state|
        raise ShiftError, 'data directory not supported'
      end,

      r_data_index_equal_with_val: lambda do |tree, state|
        raise ShiftError, 'index directory not supported'
      end,

      r_shared_table_option__CONNECTION: lambda do |tree, state|
        raise ShiftError, 'connection not supported'
      end,

      r_opt_partition_values__LESS_THAN_values: lambda do |tree, state|
        num = tree.find_top(name: :expr).eval
        if num < 0 || num % 1 != 0
          raise ShiftError, 'only natural number (>= 0) supported'
        end
      end,

      r_opt_NODEGROUP_equal_with_val__body: lambda do |tree, state|
        raise ShiftError, 'nodegroup not supported'
      end,

      # ========================
      # ======== grammar =======
      # ========================

      string__double: lambda do |tree, state|
        raise ShiftError, 'only single quoted string supported'
      end,

      ident__with_backtick: lambda do |tree, state|
        if tree.find_left(name: :opt_ident_in_backtick, subname: :inc).nil?
          raise ShiftError, 'empty identifier not supported'
        end
      end

    }
    @parser.merge_hooks! hooks
  end

  def status_check_run_type(state)
    # maybenocheckalter is always a long run. we want this option when there is at least
    # one column name that is changing
    return :maybenocheckalter if state[:run][:nocheckalter]
    return :long if state[:run][:long]
    return :short if [:drop, :create].include?(state[:action])
    return :maybeshort if state[:run][:short]
    raise ShiftInternalError, "Can't determine running type"
  end

  def check_foreign_keys(state)
    table = state[:table_names][0]

    if @checkers[:has_referenced_foreign_keys]
      if @checkers[:has_referenced_foreign_keys].call(table)
        raise ShiftError, 'table is referenced by foreign keys'
      end
    end

    if @checkers[:get_foreign_keys]
      # don't care if a table has foreign keys if we're dropping it
      unless state[:action] == :drop
        unless (@checkers[:get_foreign_keys].call(table) - state[:dropped_foreign_keys]).empty?
          raise ShiftError, 'table has foreign keys which are not all being dropped'
        end
      end
    end
  end

  def check_avoid_temporal_upgrade(state)
    if @checkers[:avoid_temporal_upgrade?]
      if @checkers[:avoid_temporal_upgrade?].call() == false && state[:action] == :alter
        long_run(state)
      end
    end
  end

  def finalize(output)
    check_foreign_keys(output[:state])
    check_avoid_temporal_upgrade(output[:state])
    {
      :stm => output[:tree].to_s.strip,
      :run => (status_check_run_type output[:state]),
      :table => output[:state][:table_names][0],
      :mode => output[:state][:mode],
      :action => output[:state][:action],
    }
  end

  def merge_checkers!(checkers)
    @checkers.merge!(checkers)
  end

  def parse_int(input)
    finalize @parser.parse(input)
  end

  def parse(input)
    begin
      parse_int(input.gsub("\r", ''))
    rescue Racc::ParseError => e
      raise ShiftError, e.message.gsub(/\(.*?\)$/, '').strip
    end
  end
end
