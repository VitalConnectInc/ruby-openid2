# test helpers
require_relative "test_helper"
require_relative "testutil"

# this library
require "ruby-openid2"
require "openid/urinorm"

class URINormTestCase < Minitest::Test
  include OpenID::TestDataMixin

  def test_normalize
    lines = read_data_file("urinorm.txt")

    while lines.length > 0

      case_name = lines.shift.strip
      actual = lines.shift.strip
      expected = lines.shift.strip
      lines.shift #=> newline

      if expected == "fail"
        begin
          OpenID::URINorm.urinorm(actual)
        rescue URI::InvalidURIError
          assert(true)
        else
          raise "Should have gotten URI error"
        end
      else
        normalized = OpenID::URINorm.urinorm(actual)

        assert_equal(expected, normalized, case_name)
      end
    end
  end
end
