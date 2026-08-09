class AddReservedToParticipations < ActiveRecord::Migration[8.1]
  def change
    add_column :participations, :reserved_until, :datetime
    add_index :participations, :reserved_until
  end
end
