# test helpers
require_relative "test_helper"

# this library
require "ruby-openid2"
require "openid/consumer/discovery"
require "openid/consumer/responses"

module OpenID
  class Consumer
    module TestResponses
      class TestSuccessResponse < Minitest::Test
        def setup
          @endpoint = OpenIDServiceEndpoint.new
          @endpoint.claimed_id = "identity_url"
        end

        def test_extension_response
          q = {
            "ns.sreg" => "urn:sreg",
            "ns.unittest" => "urn:unittest",
            "unittest.one" => "1",
            "unittest.two" => "2",
            "sreg.nickname" => "j3h",
            "return_to" => "return_to",
          }
          signed_list = q.keys.map { |k| "openid." + k }
          msg = Message.from_openid_args(q)
          resp = SuccessResponse.new(@endpoint, msg, signed_list)
          utargs = resp.extension_response("urn:unittest", false)

          assert_equal({"one" => "1", "two" => "2"}, utargs)
          sregargs = resp.extension_response("urn:sreg", false)

          assert_equal({"nickname" => "j3h"}, sregargs)
        end

        def test_extension_response_signed
          args = {
            "ns.sreg" => "urn:sreg",
            "ns.unittest" => "urn:unittest",
            "unittest.one" => "1",
            "unittest.two" => "2",
            "sreg.nickname" => "j3h",
            "sreg.dob" => "yesterday",
            "return_to" => "return_to",
            "signed" => "sreg.nickname,unittest.one,sreg.dob",
          }

          signed_list = [
            "openid.sreg.nickname",
            "openid.unittest.one",
            "openid.sreg.dob",
          ]

          msg = Message.from_openid_args(args)
          resp = SuccessResponse.new(@endpoint, msg, signed_list)

          # All args in this NS are signed, so expect all.
          sregargs = resp.extension_response("urn:sreg", true)

          assert_equal({"nickname" => "j3h", "dob" => "yesterday"}, sregargs)

          # Not all args in this NS are signed, so expect nil when
          # asking for them.
          utargs = resp.extension_response("urn:unittest", true)

          assert_nil(utargs)
        end
      end
    end
  end
end
