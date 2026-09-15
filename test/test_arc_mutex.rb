# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require "shellwords"
require "tmpdir"
require "minitest/mock"

# Check the native ABI before passing opaque storage to pthread.
class TestArcMutex < Minitest::Test
  module PThread
    extend FFI::Library
    ffi_lib "c"
    attach_function :pthread_mutex_trylock, [:pointer], :int
  end

  def test_storage_satisfies_native_mutex_abi
    size, alignment = native_mutex_layout
    storage = CrystalRuby::LibC::PThreadMutexT

    assert_operator storage.size, :>=, size
    assert_equal 0, storage.alignment % alignment

    mutex = CrystalRuby::ArcMutex.new
    assert_nil mutex.lock
    assert_nil mutex.unlock
  end

  def test_synchronize_returns_the_block_value
    assert_equal 17, (CrystalRuby::ArcMutex.new.synchronize { 17 })
    assert_equal false, (CrystalRuby::ArcMutex.new.synchronize { false })
    assert_nil(CrystalRuby::ArcMutex.new.synchronize { nil })
  end

  def test_failed_acquisition_does_not_unlock
    mutex = CrystalRuby::ArcMutex.new
    error = RuntimeError.new("acquisition failed")
    lock = -> { raise error }
    unlock = -> { flunk "must not unlock an unowned mutex" }
    mutex.stub(:lock, lock) do
      mutex.stub(:unlock, unlock) do
        assert_same error, assert_raises(RuntimeError) { mutex.synchronize { flunk "must not yield" } }
      end
    end
  end

  def test_synchronize_unlocks_after_an_exception
    mutex = CrystalRuby::ArcMutex.new
    assert_raises(RuntimeError) { mutex.synchronize { raise "release the mutex" } }
    assert_equal 0, PThread.pthread_mutex_trylock(mutex.to_ptr)
  ensure
    mutex.unlock
  end

  def test_contended_lock_allows_the_ruby_owner_to_run
    Dir.mktmpdir("crystalruby-lock") do |directory|
      log = File.join(directory, "output")
      pid = Process.spawn(RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-rcrystalruby",
                          "-e", contended_lock_script, out: log, err: log)
      status = wait_for_child(pid)
      assert status&.success?, File.read(log)
      assert_equal "acquired\n", File.read(log)
    end
  end

  private

  def contended_lock_script
    <<~RUBY
      mutex = CrystalRuby::ArcMutex.new
      mutex.lock
      waiter = Thread.new { mutex.synchronize { puts "acquired" } }
      Thread.pass until waiter.status == "sleep"
      mutex.unlock
      waiter.value
    RUBY
  end

  def wait_for_child(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      result = Process.waitpid2(pid, Process::WNOHANG)
      return result.last if result
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.01
    end
    Process.kill("KILL", pid)
    Process.waitpid(pid)
    nil
  end

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
