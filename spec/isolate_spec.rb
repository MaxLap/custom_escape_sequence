# frozen_string_literal: true

RSpec.describe "CustomEscapeSequence#isolate" do
  [
    ["hello%", ["hello", "%", ""]],
    ["hello!%", ["hello%"]],
    ["hello!!%", ["hello!", "%", ""]],
    ["hello!!!%", ["hello!%"]],
    ["hello!!!!%", ["hello!!", "%", ""]],
    ["hello%%world", ["hello", "%", "", "%", "world"]],
  ].each do |input, output|
    it "#{input.inspect} => #{output.inspect}" do
      ces = CustomEscapeSequence.new("%", escape: "!")

      expect(ces.isolate(input)).to eq(output)
    end
  end
end
