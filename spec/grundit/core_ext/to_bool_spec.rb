require "grundit/core_ext/to_bool"

RSpec.describe "to_bool core extension" do
  describe "String#to_bool" do
    it "converts 'true' to true" do
      expect("true".to_bool).to be true
    end

    it "converts 'TRUE' to true (case-insensitive)" do
      expect("TRUE".to_bool).to be true
    end

    it "converts 'True' to true (case-insensitive)" do
      expect("True".to_bool).to be true
    end

    it "converts 'false' to false" do
      expect("false".to_bool).to be false
    end

    it "converts 'FALSE' to false (case-insensitive)" do
      expect("FALSE".to_bool).to be false
    end

    it "converts an empty string to false" do
      expect("".to_bool).to be false
    end

    it "converts a whitespace-only string to false" do
      expect("   ".to_bool).to be false
    end

    it "raises ArgumentError for unconvertible strings" do
      expect { "maybe".to_bool }.to raise_error(ArgumentError, /No conversion/)
    end

    it "raises ArgumentError for numeric strings" do
      expect { "1".to_bool }.to raise_error(ArgumentError, /No conversion/)
    end
  end

  describe "TrueClass#to_bool" do
    it "returns true" do
      expect(true.to_bool).to be true
    end
  end

  describe "FalseClass#to_bool" do
    it "returns false" do
      expect(false.to_bool).to be false
    end
  end

  describe "NilClass#to_bool" do
    it "returns false" do
      expect(nil.to_bool).to be false
    end
  end
end
