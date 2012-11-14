module Bytes #:nodoc:
  module NumberHelper

    STORAGE_UNITS = [:byte, :kb, :mb, :gb, :tb].freeze

    UNIT_NAMES = {
      byte: {
        one:   "Byte",
        other: "Bytes"
      },
      kb: "KB",
      mb: "MB",
      gb: "GB",
      tb: "TB"
    }.freeze

    # Formats the bytes in +number+ into a more understandable representation
    # (e.g., giving it 1500 yields 1.5 KB). This method is useful for
    # reporting file sizes to users. You can customize the
    # format in the +options+ hash.
    #
    # See <tt>number_to_human</tt> if you want to pretty-print a generic number.
    #
    # ==== Options
    # * <tt>:locale</tt>     - Sets the locale to be used for formatting (defaults to current locale).
    # * <tt>:precision</tt>  - Sets the precision of the number (defaults to 3).
    # * <tt>:significant</tt>  - If +true+, precision will be the # of significant_digits. If +false+, the # of fractional digits (defaults to +true+)
    # * <tt>:separator</tt>  - Sets the separator between the fractional and integer digits (defaults to ".").
    # * <tt>:delimiter</tt>  - Sets the thousands delimiter (defaults to "").
    # * <tt>:strip_insignificant_zeros</tt>  - If +true+ removes insignificant zeros after the decimal separator (defaults to +true+)
    # ==== Examples
    #  to_human_size(123)                                          # => 123 Bytes
    #  to_human_size(1234)                                         # => 1.21 KB
    #  to_human_size(12345)                                        # => 12.1 KB
    #  to_human_size(1234567)                                      # => 1.18 MB
    #  to_human_size(1234567890)                                   # => 1.15 GB
    #  to_human_size(1234567890123)                                # => 1.12 TB
    #  to_human_size(1234567, :precision => 2)                     # => 1.2 MB
    #  to_human_size(483989, :precision => 2)                      # => 470 KB
    #  to_human_size(1234567, :precision => 2, :separator => ',')  # => 1,2 MB
    #
    # Non-significant zeros after the fractional separator are stripped out by default (set
    # <tt>:strip_insignificant_zeros</tt> to +false+ to change that):
    #  to_human_size(1234567890123, :precision => 5)        # => "1.1229 TB"
    #  to_human_size(524288000, :precision=>5)              # => "500 MB"
    def to_human_size(options = {})
      number = Float(self)

      storage_units_format = "%n %u"

      if number.to_i < 1024
        unit = UNIT_NAMES[:byte][:other]
        storage_units_format.gsub(/%n/, number.to_i.to_s).gsub(/%u/, unit)
      else
        max_exp  = STORAGE_UNITS.size - 1
        exponent = (Math.log(number) / Math.log(1024)).to_i # Convert to base 1024
        exponent = max_exp if exponent > max_exp # we need this to avoid overflow for the highest unit
        number  /= 1024 ** exponent

        unit_key = STORAGE_UNITS[exponent]
        unit = UNIT_NAMES[unit_key.to_sym]

        formatted_number = "%.02f" % number
        storage_units_format.gsub(/%n/, formatted_number).gsub(/%u/, unit)
      end
    end
  end
end

class Numeric
  include Bytes::NumberHelper
end