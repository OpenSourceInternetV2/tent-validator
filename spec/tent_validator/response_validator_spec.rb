require 'spec_helper'

class TestValidator < TentValidator::ResponseValidator
  register :test

  def validate(options)
    expect(:body => 'test')
    super
  end
end

describe TentValidator::ResponseValidator do
  it "should register custom validators" do
    expect(described_class.validate(:test) { stub(:body => 'test') }).to be_passed
    expect(described_class.validate(:test) { stub(:body => nil) }).to_not be_passed
  end

  it "should raise exception when specified validator doesn't exist" do
    expect(lambda {
      described_class.validate(:unknown)
    }).to raise_error(described_class::ValidatorNotFoundError)
  end
end

describe TentValidator::ResponseValidator::Expectation do
  context 'response body' do
    it 'should set expectation for exact match of response body' do
      expectation = described_class.new(
        :body => 'test'
      )

      response = stub(:body => 'test')
      expect(
        expectation.validate(response)
      ).to be_true

      response = stub(:body => 'unexpected')
      expect(
        expectation.validate(response)
      ).to be_false
    end

    it 'should set expectation for partial match of response body'

    it 'should set expectation for deep partial match of response body'
  end

  context 'response headers' do
    it 'should set expectation that specified headers be included with exact values'

    it 'should set expectation that specified headers be included with approximate values'
  end

  context 'response status' do
    it 'should set expectation for exact response status'

    it 'should set expectation that response status is in given range'

    it 'should default to expecting 2xx'
  end
end
