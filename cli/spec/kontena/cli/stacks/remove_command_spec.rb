require_relative "../../../spec_helper"
require "kontena/cli/stacks/remove_command"

describe Kontena::Cli::Stacks::RemoveCommand do

  include ClientHelpers

  describe '#execute' do
    it 'requires api url' do
      allow(subject).to receive(:forced?).and_return(true)
      allow(subject).to receive(:wait_stack_removal)
      expect(subject).to receive(:require_api_url).once
      subject.run(['test-stack'])
    end

    it 'requires token' do
      allow(subject).to receive(:forced?).and_return(true)
      allow(subject).to receive(:wait_stack_removal)
      expect(subject).to receive(:require_token).and_return(token)
      subject.run(['test-stack'])
    end

    it 'sends remove command to master' do
      allow(subject).to receive(:wait_stack_removal)
      expect(client).to receive(:delete).with('stacks/test-grid/test-stack')
      subject.run(['--force', 'test-stack'])
    end

    it 'waits until service is removed' do
      allow(client).to receive(:delete).with('stacks/test-grid/test-stack')
      expect(client).to receive(:get).with('stacks/test-grid/test-stack')
        .and_raise(Kontena::Errors::StandardError.new(404, 'Not Found'))
      subject.run(['--force', 'test-stack'])
    end

    it 'raises exception on server error' do
      expect(client).to receive(:delete).with('stacks/test-grid/test-stack')
      expect(client).to receive(:get).with('stacks/test-grid/test-stack')
        .and_raise(Kontena::Errors::StandardError.new(500, 'internal error'))
      expect{
        subject.run(['--force', 'test-stack'])
      }.to raise_error(Kontena::Errors::StandardError)
    end
  end
end
