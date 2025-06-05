ActiveRecord::Schema.define do
  self.verbose = false

  create_table :users, force: true do |t|
    t.string :name
    t.string :email
    t.string :department
    t.integer :salary
    t.date :hire_date
    t.boolean :active, default: true
    t.timestamps
  end

  # Add indexes for better performance in window function tests
  add_index :users, :department
  add_index :users, :hire_date
end
