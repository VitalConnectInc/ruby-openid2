# test helpers
require_relative "test_helper"
require_relative "util"

# this library
require "ruby-openid2"
require "openid/kvform"
require "openid/util"

include OpenID

class KVFormTests < Minitest::Test
  include OpenID::TestUtil

  def test_kvdict
    [
      # (kvform, parsed dictionary, expected warnings)
      ["", {}, 0],
      ["\n  \n     \n", {}, 0],
      ["college:harvey mudd\n", {"college" => "harvey mudd"}, 0],
      [
        "city:claremont\nstate:CA\n",
        {"city" => "claremont", "state" => "CA"},
        0,
      ],
      [
        "is_valid:true\ninvalidate_handle:{HMAC-SHA1:2398410938412093}\n",
        {
          "is_valid" => "true",
          "invalidate_handle" => "{HMAC-SHA1:2398410938412093}",
        },
        0,
      ],

      # Warnings from lines with no colon:
      ["x\n", {}, 1],
      ["x\nx\n", {}, 2],
      ["East is least\n", {}, 1],

      # But not from blank lines (because LJ generates them)
      ["x\n\n", {}, 1],

      # Warning from empty key
      [":\n", {"" => ""}, 1],
      [":missing key\n", {"" => "missing key"}, 1],

      # Warnings from leading or trailing whitespace in key or value
      [" street:foothill blvd\n", {"street" => "foothill blvd"}, 1],
      ["major: computer science\n", {"major" => "computer science"}, 1],
      [" dorm : east \n", {"dorm" => "east"}, 2],

      # Warnings from missing trailing newline
      ["e^(i*pi)+1:0", {"e^(i*pi)+1" => "0"}, 1],
      ["east:west\nnorth:south", {"east" => "west", "north" => "south"}, 1],
    ].each do |case_|
      _run_kvdictTest(case_)
    end
  end

  def _run_kvdictTest(case_)
    kv, dct, warnings = case_

    d = nil
    d2 = nil
    assert_log_line_count(warnings) do
      # Convert KVForm to dict
      d = Util.kv_to_dict(kv)

      # Strict mode should raise KVFormError instead of logging
      # messages
      if warnings > 0
        assert_raises(KVFormError) do
          Util.kv_to_seq(kv, true)
        end
      end

      # make sure it parses to expected dict
      assert_equal(dct, d)
    end

    # Convert back to KVForm and round-trip back to dict to make sure
    # that *** dict -> kv -> dict is identity. ***
    kv = Util.dict_to_kv(d)

    silence_logging do
      d2 = Util.kv_to_dict(kv)
    end

    assert_equal(d, d2)
  end

  def test_kvseq
    [
      [[], "", 0],

      [[%w[openid useful], %w[a b]], "openid:useful\na:b\n", 0],

      # Warnings about leading whitespace
      [[[" openid", "useful"], ["a", "b"]], " openid:useful\na:b\n", 2],

      # Warnings about leading and trailing whitespace
      [
        [
          [" openid ", " useful "],
          [" a ", " b "],
        ],
        " openid : useful \n a : b \n",
        8,
      ],

      # warnings about leading and trailing whitespace, but not about
      # internal whitespace.
      [
        [
          [" open id ", " use ful "],
          [" a ", " b "],
        ],
        " open id : use ful \n a : b \n",
        8,
      ],

      [[%w[foo bar]], "foo:bar\n", 0],
    ].each do |case_|
      _run_kvseqTest(case_)
    end
  end

  def _cleanSeq(seq)
    # Create a new sequence by stripping whitespace from start and end
    # of each value of each pair
    seq.collect { |k, v| [k.strip, v.strip] }
  end

  def _run_kvseqTest(case_)
    seq, kvform, warnings = case_

    assert_log_line_count(warnings) do
      # seq serializes to expected kvform
      actual = Util.seq_to_kv(seq)

      assert_equal(kvform, actual)
      assert_kind_of(String, actual)

      # Strict mode should raise KVFormError instead of logging
      # messages
      if warnings > 0
        assert_raises(KVFormError) do
          Util.seq_to_kv(seq, true)
        end
      end

      # Parse back to sequence. Expected to be unchanged, except
      # stripping whitespace from start and end of values
      # (i. e. ordering, case, and internal whitespace is preserved)
      seq = Util.kv_to_seq(actual)
      clean_seq = _cleanSeq(seq)

      assert_equal(seq, clean_seq)
    end
  end

  def test_kvexc
    [
      [%W[openid use\nful]],
      [%W[open\nid useful]],
      [%W[open\nid use\nful]],
      [["open:id", "useful"]],
      [["foo", "bar"], ["ba\n d", "seed"]],
      [["foo", "bar"], ["bad:", "seed"]],
    ].each do |case_|
      _run_kvexcTest(case_)
    end
  end

  def _run_kvexcTest(case_)
    seq = case_

    assert_raises(KVFormError) do
      Util.seq_to_kv(seq)
    end
  end

  def test_convert
    assert_log_line_count(2) do
      result = Util.seq_to_kv([[1, 1]])

      assert_equal("1:1\n", result)
    end
  end
end
