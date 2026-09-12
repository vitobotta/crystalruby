# frozen_string_literal: true

require_relative "test_helper"

class TestGCActive < Minitest::Test
  module ::MemoryGobbler
    crystal lib: "memory_gobbler" do
      @@leaked_memory = ""
    end

    crystallize lib: "memory_gobbler"
    def gobble_gcable_memory(mb: :float)
      "a" * (mb * 1024 * 1024).to_i
    end

    crystallize lib: "memory_gobbler"
    def leak_memory(mb: :float)
      @@leaked_memory += "a" * (mb * 1024 * 1024).to_i
    end

    crystallize :uint64, async: true, lib: "memory_gobbler"
    def trigger_gc
      5.times do
        sleep 0.001.seconds
        GC.collect
      end
      GC.stats.heap_size
    end
  end

  class ObjectAllocTest < CRType do
    NamedTuple(hash: Hash(Int32, Int32), string: String, array: Array(Int32))
  end
  end

  crystallize
  def crystal_gc
    GC.collect
  end

  crystallize
  def crystal_alloc(returns: ObjectAllocTest)
    ObjectAllocTest.new({ hash: { 1 => 2 }, string: "hello", array: [1, 2, 3] })
  end

  crystallize
  def store_for_later(value: ObjectAllocTest)
    @@value = value
  end

  crystallize
  def clear_stored_value
    @@value = nil
    GC.collect
  end

  crystallize -> { TestGCActive::ObjectAllocTest }
  def stored_value
    @@value.not_nil!
  end

  def test_ruby_alloc_crystal_free
    value = { hash: { 3 => 4 }, string: "retained", array: [5, 6] }

    10.times do
      store_for_later(ObjectAllocTest.new(value))
      GC.start
      assert_equal value, stored_value.native
      GC.start
      clear_stored_value
    end
  end

  def test_crystal_alloc_ruby_free
    10.times do
      object = crystal_alloc
      crystal_gc
      assert_equal({ hash: { 1 => 2 }, string: "hello", array: [1, 2, 3] }, object.native)
      GC.start
    end
  end
end
