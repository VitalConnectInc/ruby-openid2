# stdlib
require "uri"

# test helpers
require_relative "test_helper"
require_relative "testutil"
require_relative "discoverdata"

# this library
require "ruby-openid2"
require "openid/yadis/discovery"
require "openid/fetchers"
require "openid/util"

module OpenID
  module YadisDiscovery
    include FetcherMixin
    include DiscoverData

    STATUS_HEADER_RE = /Status: (\d+) .*?$/m

    def self.mkResponse(data)
      status_mo = data.scan(STATUS_HEADER_RE)
      headers_str, body = data.split("\n\n", 2)
      headers = {}
      headers_str.split("\n", -1).each do |line|
        k, v = line.split(":", 2)
        k = k.strip.downcase
        v = v.strip
        headers[k] = v
      end
      status = status_mo[0][0].to_i
      HTTPResponse._from_raw_data(
        status,
        body,
        headers,
      )
    end

    class TestFetcher
      include DiscoverData

      def initialize(base_url)
        @base_url = base_url
      end

      def fetch(url, _headers, _body, _redirect_limit = nil)
        current_url = url
        while true
          parsed = URI.parse(current_url)
          # parsed[2][1:]
          path = parsed.path[1..-1]
          begin
            data = generateSample(path, @base_url)
          rescue ArgumentError
            return HTTPResponse._from_raw_data(
              404,
              "",
              {},
              current_url,
            )
          end

          response = YadisDiscovery.mkResponse(data)
          if %w[301 302 303 307].member?(response.code)
            current_url = response["location"]
          else
            response.final_url = current_url
            return response
          end
        end
      end
    end

    class MockFetcher
      def initialize
        @count = 0
      end

      def fetch(uri, headers = nil, _body = nil, _redirect_limit = nil)
        @count += 1
        return HTTPResponse._from_raw_data(404, "", {}, uri) unless @count == 1

        headers = {
          "X-XRDS-Location".downcase => "http://unittest/404",
        }
        HTTPResponse._from_raw_data(200, "", headers, uri)
      end
    end

    class TestSecondGet < Minitest::Test
      include FetcherMixin

      def test_404
        uri = "http://something.unittest/"
        assert_raises(DiscoveryFailure) do
          with_fetcher(MockFetcher.new) { Yadis.discover(uri) }
        end
      end
    end

    class DiscoveryTestCase
      include DiscoverData
      include FetcherMixin

      def initialize(testcase, input_name, id_name, result_name, success)
        @base_url = "http://invalid.unittest/"
        @testcase = testcase
        @input_name = input_name
        @id_name = id_name
        @result_name = result_name
        @success = success
      end

      def setup
        @input_url, @expected = generateResult(
          @base_url,
          @input_name,
          @id_name,
          @result_name,
          @success,
        )
      end

      def do_discovery
        with_fetcher(TestFetcher.new(@base_url)) do
          Yadis.discover(@input_url)
        end
      end

      def runCustomTest
        setup

        if @expected.respond_to?(:ancestors) and @expected.ancestors.member?(DiscoveryFailure)
          @testcase.assert_raises(DiscoveryFailure) do
            do_discovery
          end
        else
          result = do_discovery

          @testcase.assert_equal(@input_url, result.request_uri)

          msg = format(
            "Identity URL mismatch: actual = %s, expected = %s",
            result.normalized_uri,
            @expected.normalized_uri,
          )

          @testcase.assert_equal(@expected.normalized_uri, result.normalized_uri, msg)

          msg = format(
            "Content mismatch: actual = %s, expected = %s",
            result.response_text,
            @expected.response_text,
          )

          @testcase.assert_equal(@expected.response_text, result.response_text, msg)

          expected_keys = @expected.instance_variables
          expected_keys.sort!

          actual_keys = result.instance_variables
          actual_keys.sort!

          @testcase.assert_equal(actual_keys, expected_keys)

          @expected.instance_variables.each do |k|
            exp_v = @expected.instance_variable_get(k)
            act_v = result.instance_variable_get(k)

            @testcase.assert_equal(act_v, exp_v, [k, exp_v, act_v])
          end
        end
      end
    end

    class NoContentTypeFetcher
      def fetch(_url, _body = nil, _headers = nil, _redirect_limit = nil)
        OpenID::HTTPResponse._from_raw_data(200, "", {}, nil)
      end
    end

    class BlankContentTypeFetcher
      def fetch(_url, _body = nil, _headers = nil, _redirect_limit = nil)
        OpenID::HTTPResponse._from_raw_data(200, "", {"Content-Type" => ""}, nil)
      end
    end

    class TestYadisDiscovery < Minitest::Test
      include FetcherMixin

      def test_yadis_discovery
        DiscoverData::TESTLIST.each do |success, input_name, id_name, result_name|
          test = DiscoveryTestCase.new(self, input_name, id_name, result_name, success)
          test.runCustomTest
        end
      end

      def test_is_xrds_yadis_location
        result = Yadis::DiscoveryResult.new("http://request.uri/")
        result.normalized_uri = "http://normalized/"
        result.xrds_uri = "http://normalized/xrds"

        assert(result.is_xrds)
      end

      def test_is_xrds_content_type
        result = Yadis::DiscoveryResult.new("http://request.uri/")
        result.normalized_uri = result.xrds_uri = "http://normalized/"
        result.content_type = Yadis::YADIS_CONTENT_TYPE

        assert(result.is_xrds)
      end

      def test_is_xrds_neither
        result = Yadis::DiscoveryResult.new("http://request.uri/")
        result.normalized_uri = result.xrds_uri = "http://normalized/"
        result.content_type = "another/content-type"

        assert(!result.is_xrds)
      end

      def test_no_content_type
        with_fetcher(NoContentTypeFetcher.new) do
          result = Yadis.discover("http://bogus")

          assert_nil(result.content_type)
        end
      end

      def test_blank_content_type
        with_fetcher(BlankContentTypeFetcher.new) do
          result = Yadis.discover("http://bogus")

          assert_equal("", result.content_type)
        end
      end
    end
  end
end
