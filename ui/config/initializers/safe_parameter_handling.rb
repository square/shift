# Disable symbol, YAML, and JSON parsing in the XML parser to avoid
# other code paths being exploited.
#
ActionDispatch::ParamsParser::DEFAULT_PARSERS.delete(Mime::XML)
ActionDispatch::ParamsParser::DEFAULT_PARSERS.delete(Mime::YAML)
#ActionDispatch::ParamsParser::DEFAULT_PARSERS.delete(Mime::JSON)

ActiveSupport::XmlMini::PARSING.delete("symbol")
ActiveSupport::XmlMini::PARSING.delete("yaml")
