# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require "shellwords"
require "tmpdir"

# Check the native ABI before passing opaque storage to pthread.
class TestArcMutex < Minitest::Test
  def test_storage_satisfies_native_mutex_abi
    size, alignment = native_mutex_layout
    storage = CrystalRuby::LibC::PThreadMutexT

    assert_operator storage.size, :>=, size
    assert_equal 0, storage.alignment % alignment

    mutex = CrystalRuby::ArcMutex.new
    assert_nil mutex.lock
    assert_nil mutex.unlock
  end

  private

  def native_mutex_layout
    Dir.mktmpdir("crystalruby-mutex") do |directory|
      executable = File.join(directory, "mutex_layout")
      compile_mutex_layout(executable)

      output, status = Open3.capture2e(executable)
      assert status.success?, output
      output.split.map(&:to_i)
    end
  end

  def compile_mutex_layout(executable)
    compiler = Shellwords.split(RbConfig::CONFIG.fetch("CC"))
    output, status = Open3.capture2e(*compiler, "-std=c11", "-x", "c", "-o", executable, "-", stdin_data: <<~C)
      #include <pthread.h>
      #include <stdio.h>

      int main(void) {
        printf("%zu %zu\\n", sizeof(pthread_mutex_t), _Alignof(pthread_mutex_t));
        return 0;
      }
    C
    assert status.success?, output
  end
end
