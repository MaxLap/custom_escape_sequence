# frozen_string_literal: true

RSpec.describe "CustomEscapeSequence.split_on_isolated" do
  [
    [["hi", "!", "world"], [["hi"], ["world"]]],
    [["hi", "!", "", "%", "world"], [["hi"], ["", "%", "world"]]],
    [["hi", "!", "!", "!", "world"], [["hi"], ["!"], ["world"]]]
  ].each do |input, output|
    it "#{input.inspect} => #{output.inspect}" do
      expect(CustomEscapeSequence.split_on_isolated(input, "!")).to eq(output)
    end
  end
end
