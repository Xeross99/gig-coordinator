# Wyłączanie konta zamiast kasowania — timestamp mówi też KIEDY wyłączono.
class AddDisabledAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :disabled_at, :datetime
  end
end
