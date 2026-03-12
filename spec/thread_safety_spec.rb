# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.

# This source code is licensed under the license found in the
# LICENSE file in the root directory of this source tree.

RSpec.describe 'Thread safety' do
  describe 'Session isolation' do
    before do
      Thread.current[:facebook_ads_current_session] = nil
    end

    after do
      Thread.current[:facebook_ads_current_session] = nil
    end

    it 'isolates current_session per thread' do
      t1_ready = Queue.new
      t2_ready = Queue.new
      results = {}

      t1 = Thread.new do
        session = FacebookAds::Session.new(access_token: 'token_thread_1')
        FacebookAds::Session.current_session = session
        t1_ready.push(:ready)
        t2_ready.pop # wait for t2 to set its session
        results[:t1] = FacebookAds::Session.current_session.access_token
      end

      t2 = Thread.new do
        t1_ready.pop # wait for t1 to set its session
        session = FacebookAds::Session.new(access_token: 'token_thread_2')
        FacebookAds::Session.current_session = session
        t2_ready.push(:ready)
        results[:t2] = FacebookAds::Session.current_session.access_token
      end

      t1.join(5)
      t2.join(5)

      expect(results[:t1]).to eq('token_thread_1')
      expect(results[:t2]).to eq('token_thread_2')
    end

    it 'isolates with_session per thread' do
      t1_ready = Queue.new
      t2_ready = Queue.new
      results = {}

      t1 = Thread.new do
        FacebookAds.with_session('with_token_1') do
          t1_ready.push(:ready)
          t2_ready.pop
          results[:t1] = FacebookAds::Session.current_session.access_token
        end
      end

      t2 = Thread.new do
        t1_ready.pop
        FacebookAds.with_session('with_token_2') do
          t2_ready.push(:ready)
          results[:t2] = FacebookAds::Session.current_session.access_token
        end
      end

      t1.join(5)
      t2.join(5)

      expect(results[:t1]).to eq('with_token_1')
      expect(results[:t2]).to eq('with_token_2')
    end
  end

  describe 'Batch isolation' do
    after do
      Thread.current[:facebook_ads_current_batch] = nil
    end

    it 'isolates current_batch per thread' do
      t1_ready = Queue.new
      t2_ready = Queue.new
      results = {}

      t1 = Thread.new do
        batch1 = FacebookAds::Batch.new
        FacebookAds::Batch.current_batch = batch1
        t1_ready.push(:ready)
        t2_ready.pop
        results[:t1] = FacebookAds::Batch.current_batch.object_id
        results[:t1_batch] = batch1.object_id
        FacebookAds::Batch.current_batch = nil
      end

      t2 = Thread.new do
        t1_ready.pop
        batch2 = FacebookAds::Batch.new
        FacebookAds::Batch.current_batch = batch2
        t2_ready.push(:ready)
        results[:t2] = FacebookAds::Batch.current_batch.object_id
        results[:t2_batch] = batch2.object_id
        FacebookAds::Batch.current_batch = nil
      end

      t1.join(5)
      t2.join(5)

      expect(results[:t1]).to eq(results[:t1_batch])
      expect(results[:t2]).to eq(results[:t2_batch])
      expect(results[:t1]).not_to eq(results[:t2])
    end

    it 'isolates with_batch per thread' do
      t1_ready = Queue.new
      t2_ready = Queue.new
      batches = {}

      t1 = Thread.new do
        FacebookAds::Batch.with_batch do
          batches[:t1] = FacebookAds::Batch.current_batch.object_id
          t1_ready.push(:ready)
          t2_ready.pop
        end
      end

      t2 = Thread.new do
        t1_ready.pop
        FacebookAds::Batch.with_batch do
          batches[:t2] = FacebookAds::Batch.current_batch.object_id
          t2_ready.push(:ready)
        end
      end

      t1.join(5)
      t2.join(5)

      expect(batches[:t1]).not_to eq(batches[:t2])
    end
  end

  describe 'FieldTypes registry' do
    it 'returns correct types after concurrent lookups' do
      results = Array.new(10) { {} }
      threads = 10.times.map do |i|
        Thread.new do
          results[i][:string] = FacebookAds::FieldTypes.lookup('string')
          results[i][:int] = FacebookAds::FieldTypes.lookup('int')
          results[i][:list] = FacebookAds::FieldTypes.lookup('list')
        end
      end
      threads.each { |t| t.join(5) }

      results.each do |r|
        expect(r[:string]).not_to be_nil
        expect(r[:int]).not_to be_nil
        expect(r[:list]).not_to be_nil
        expect(r[:string]).to eq(results[0][:string])
        expect(r[:int]).to eq(results[0][:int])
        expect(r[:list]).to eq(results[0][:list])
      end
    end
  end

  describe 'CrashLogger' do
    it 'does not raise under concurrent enable/disable' do
      threads = 20.times.map do |i|
        Thread.new do
          if i.even?
            FacebookAds::CrashLogger.enable
          else
            FacebookAds::CrashLogger.disable
          end
        end
      end

      expect { threads.each { |t| t.join(5) } }.not_to raise_error
    end
  end
end
