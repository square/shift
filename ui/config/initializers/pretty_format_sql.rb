class String
  def pretty_format_sql
    require "anbt-sql-formatter/formatter"
    rule = AnbtSql::Rule.new
    rule.keyword = AnbtSql::Rule::KEYWORD_UPPER_CASE
    rule.kw_plus1_indent_x_nl = %w(INSERT INTO TRUNCATE TABLE CASE)
    %w(count sum).each do |function_name|
      rule.function_names << function_name
    end
    rule.indent_string = "\t"
    AnbtSql::Formatter.new(rule).format(self.squeeze(" "))
  end
end
