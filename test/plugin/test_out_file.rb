require 'fluent/test'
require 'fileutils'
require 'time'

class FileOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
    FileUtils.rm_rf(TMP_DIR)
    FileUtils.mkdir_p(TMP_DIR)
  end

  TMP_DIR = File.expand_path(File.dirname(__FILE__) + "/../tmp/out_file#{ENV['TEST_ENV_NUMBER']}")
  SYMLINK_PATH = File.expand_path("#{TMP_DIR}/current")

  CONFIG = %[
    path #{TMP_DIR}/out_file_test
    compress gz
    utc
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::BufferedOutputTestDriver.new(Fluent::FileOutput).configure(conf)
  end

  def test_configure
    d = create_driver %[
      path test_path
      compress gz
    ]
    assert_equal 'test_path', d.instance.path
    assert_equal :gz, d.instance.compress
  end

  def test_format
    d = create_driver

    time = Time.parse("2011-01-02 13:14:15 UTC").to_i
    d.emit({"a"=>1}, time)
    d.emit({"a"=>2}, time)

    d.expect_format %[2011-01-02T13:14:15Z\ttest\t{"a":1}\n]
    d.expect_format %[2011-01-02T13:14:15Z\ttest\t{"a":2}\n]

    d.run
  end

  def test_write
    d = create_driver

    time = Time.parse("2011-01-02 13:14:15 UTC").to_i
    d.emit({"a"=>1}, time)
    d.emit({"a"=>2}, time)

    # FileOutput#write returns path
    path = d.run
    expect_path = "#{TMP_DIR}/out_file_test._0.log.gz"
    assert_equal expect_path, path

    data = Zlib::GzipReader.open(expect_path) {|f| f.read }
    assert_equal %[2011-01-02T13:14:15Z\ttest\t{"a":1}\n] + %[2011-01-02T13:14:15Z\ttest\t{"a":2}\n],
                 data
  end

  def check_gzipped_result(path, expect)
    # Zlib::GzipReader has a bug of concatenated file: https://bugs.ruby-lang.org/issues/9790
    # Following code from https://www.ruby-forum.com/topic/971591#979520
    result = ''
    File.open(path) { |io|
      loop do
        gzr = Zlib::GzipReader.new(io)
        result << gzr.read
        unused = gzr.unused
        gzr.finish
        break if unused.nil?
        io.pos -= unused.length
      end
    }

    assert_equal expect, result
  end

  def test_write_path_increment
    d = create_driver

    time = Time.parse("2011-01-02 13:14:15 UTC").to_i
    d.emit({"a"=>1}, time)
    d.emit({"a"=>2}, time)
    formatted_lines = %[2011-01-02T13:14:15Z\ttest\t{"a":1}\n] + %[2011-01-02T13:14:15Z\ttest\t{"a":2}\n]

    # FileOutput#write returns path
    path = d.run
    assert_equal "#{TMP_DIR}/out_file_test._0.log.gz", path
    check_gzipped_result(path, formatted_lines)
    path = d.run
    assert_equal "#{TMP_DIR}/out_file_test._1.log.gz", path
    check_gzipped_result(path, formatted_lines)
    path = d.run
    assert_equal "#{TMP_DIR}/out_file_test._2.log.gz", path
    check_gzipped_result(path, formatted_lines)
  end

  def test_write_with_append
    d = create_driver %[
      path #{TMP_DIR}/out_file_test
      compress gz
      utc
      append true
    ]

    time = Time.parse("2011-01-02 13:14:15 UTC").to_i
    d.emit({"a"=>1}, time)
    d.emit({"a"=>2}, time)
    formatted_lines = %[2011-01-02T13:14:15Z\ttest\t{"a":1}\n] + %[2011-01-02T13:14:15Z\ttest\t{"a":2}\n]

    # FileOutput#write returns path
    path = d.run
    assert_equal "#{TMP_DIR}/out_file_test..log.gz", path
    check_gzipped_result(path, formatted_lines)
    path = d.run
    assert_equal "#{TMP_DIR}/out_file_test..log.gz", path
    check_gzipped_result(path, formatted_lines * 2)
    path = d.run
    assert_equal "#{TMP_DIR}/out_file_test..log.gz", path
    check_gzipped_result(path, formatted_lines * 3)
  end

  def test_write_with_symlink
    conf = CONFIG + %[
      symlink_path #{SYMLINK_PATH}
    ]
    symlink_path = "#{SYMLINK_PATH}"

    Fluent::FileBuffer.clear_buffer_paths
    d = Fluent::Test::TestDriver.new(Fluent::FileOutput).configure(conf)

    begin
      d.instance.start
      10.times { sleep 0.05 }
      time = Time.parse("2011-01-02 13:14:15 UTC").to_i
      es = Fluent::OneEventStream.new(time, {"a"=>1})
      d.instance.emit('tag', es, Fluent::NullOutputChain.instance)

      assert File.exists?(symlink_path)
      assert File.symlink?(symlink_path)

      d.instance.enqueue_buffer

      assert !File.exists?(symlink_path)
      assert File.symlink?(symlink_path)
    ensure
      d.instance.shutdown
      FileUtils.rm_rf(symlink_path)
    end
  end
end

