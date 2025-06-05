require "spec_helper"

describe ActiveWindows::ActiveRecordExtensions do
  it "extends ActiveRecord::Base with window functions" do
    expect(User).to respond_to(:window)
    expect(User).to respond_to(:row_number)
  end

  it "can create window functions" do
    # Create some test data
    User.create!(name: "Alice", department: "Engineering", salary: 80000, hire_date: Date.new(2020, 1, 1))
    User.create!(name: "Bob", department: "Engineering", salary: 90000, hire_date: Date.new(2021, 1, 1))
    User.create!(name: "Charlie", department: "Sales", salary: 70000, hire_date: Date.new(2020, 6, 1))

    # Test that window functions can be created without errors
    expect {
      User.window(row_number: { partition: :department, order: :salary, as: :rank })
    }.not_to raise_error
  end
end
