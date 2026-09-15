# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"

# Exercise ownership decisions without freeing the probe's memory.
class TestReferenceCounting < Minitest::Test
  module Native
    crystal raw: true, lib: "reference_counting" do
      <<~CRYSTAL
        class ReleaseProbe < CrystalRuby::Types::FixedWidth
          class_property frees = 0
          class_property locked = false
          class_property release_other = true
          class_property pointer = Pointer(UInt8).null

          def self.synchronize
            self.locked = true
            result = yield
            self.locked = false
            if self.release_other
              self.release_other = false
              decrement_ref_count!(pointer)
            end
            result
          end

          def self.free!(memory)
            raise "destruction is inside the lock" if locked
            self.frees += 1
          end
        end
      CRYSTAL
    end

    crystallize :bool, raw: true, lib: "reference_counting"
    def uses_shared_mutex
      <<~CRYSTAL
        return false if CrystalRuby.rc_mux.null?
        locked = false
        mutex = CrystalRuby.rc_mux.as(Pointer(LibC::PthreadMutexT))
        CrystalRuby::Types::Type.synchronize do
          locked = LibC.pthread_mutex_trylock(mutex) != 0
          LibC.pthread_mutex_unlock(mutex) unless locked
        end
        locked
      CRYSTAL
    end

    crystallize :int32, raw: true, lib: "reference_counting"
    def synchronization_value
      "CrystalRuby::Types::Type.synchronize { 17 }"
    end

    crystallize :bool, raw: true, lib: "reference_counting"
    def unlocks_after_exception
      <<~CRYSTAL
        return false if CrystalRuby.rc_mux.null?
        begin
          CrystalRuby::Types::Type.synchronize { raise "release the mutex" }
        rescue
        end
        mutex = CrystalRuby.rc_mux.as(Pointer(LibC::PthreadMutexT))
        result = LibC.pthread_mutex_trylock(mutex)
        LibC.pthread_mutex_unlock(mutex)
        result == 0
      CRYSTAL
    end

    crystallize :int32, raw: true, lib: "reference_counting"
    def final_release_count
      <<~CRYSTAL
        pointer = Pointer(UInt32).malloc(1, 2_u32)
        ReleaseProbe.pointer = pointer.as(Pointer(UInt8))
        ReleaseProbe.frees = 0
        ReleaseProbe.release_other = true
        ReleaseProbe.decrement_ref_count!(ReleaseProbe.pointer)
        ReleaseProbe.frees
      CRYSTAL
    end

    crystallize :uint64, raw: true, lib: "reference_counting"
    def mutex_address
      "CrystalRuby.rc_mux.address"
    end
  end

  def test_native_runtime_keeps_the_ruby_mutex_address
    assert_equal CrystalRuby::Types::Type::ARC_MUTEX.to_ptr.address, Native.mutex_address
  end

  def test_native_runtime_exports_release_the_gvl
    Native.mutex_address
    library = CrystalRuby::Library["reference_counting"]
    bindings = {}
    attach = library.singleton_class.method(:attach_function)
    recorder = lambda do |*args|
      bindings[args.first] = args.last
      attach.call(*args)
    end
    library.singleton_class.stub(:attach_function, recorder) { library.attach! }

    assert_equal(%i[init yield gc stop].to_h { |name| [name, { blocking: true }] }, bindings)
  end

  def test_native_reference_counts_use_the_shared_mutex
    assert Native.uses_shared_mutex
  end

  def test_native_synchronization_returns_the_block_value
    assert_equal 17, Native.synchronization_value
  end

  def test_native_synchronization_unlocks_after_an_exception
    assert Native.unlocks_after_exception
  end

  def test_native_final_release_has_only_one_owner
    assert_equal 1, Native.final_release_count
  end

  def test_ruby_final_release_has_only_one_owner
    memory = FFI::MemoryPointer.new(:int32)
    memory.write_int32(2)
    frees = []
    probe = release_probe(memory: memory, frees: frees)

    probe.decrement_ref_count!(memory)

    assert_equal 0, memory.read_int32
    assert_equal [memory.address], frees
  end

  private

  def release_probe(memory:, frees:)
    mutex = Mutex.new
    synchronize = release_after_unlock(memory: memory, mutex: mutex)
    Class.new(CrystalRuby::Types::FixedWidth) do
      define_singleton_method(:synchronize, &synchronize)
      define_singleton_method(:free!) do |pointer|
        raise "destruction is inside the lock" if mutex.owned?

        frees << pointer.address
      end
    end
  end

  def release_after_unlock(memory:, mutex:)
    release_other = true
    proc do |&block|
      result = mutex.synchronize(&block)
      if release_other
        release_other = false
        decrement_ref_count!(memory)
      end
      result
    end
  end
end
