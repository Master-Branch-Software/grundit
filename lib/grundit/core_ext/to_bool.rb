# Opt-in core extension that adds #to_bool to String, TrueClass, FalseClass, and NilClass.
#
# Useful when boolean values arrive as strings from form posts, GraphQL inputs,
# or environment variables and need uniform conversion.
#
# Usage:
#   require "grundit/core_ext/to_bool"
#
#   "true".to_bool   # => true
#   "false".to_bool  # => false
#   "".to_bool       # => false
#   true.to_bool     # => true
#   false.to_bool    # => false
#   nil.to_bool      # => false

class String
  def to_bool
    if match?(/true/i)
      return true
    end

    if match?(/false/i) || strip.empty?
      return false
    end

    raise ArgumentError, "No conversion of '#{self}' to boolean."
  end
end

class TrueClass
  def to_bool
    self
  end
end

class FalseClass
  def to_bool
    self
  end
end

class NilClass
  def to_bool
    false
  end
end
