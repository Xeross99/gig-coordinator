class AllowNullEmailOnHosts < ActiveRecord::Migration[8.1]
  def change
    change_column_null :hosts, :email, true
  end
end
