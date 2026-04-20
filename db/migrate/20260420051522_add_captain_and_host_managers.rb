class AddObiektowyKomendantAndHostManagers < ActiveRecord::Migration[8.1]
  # Renumeruje istniejących `master` z wartości 3 na 4, a następnie
  # tworzy tabelę `host_managers`. Kolejność jest ważna: enum po tej migracji
  # mapuje wartość 3 na `captain` (nowa ranga), więc bez UPDATE
  # istniejący mistrzowie zostaliby błędnie przeklasyfikowani.
  def up
    execute "UPDATE users SET title = 4 WHERE title = 3"

    create_table :host_managers do |t|
      t.references :user, null: false, foreign_key: true
      t.references :host, null: false, foreign_key: true, index: false
      t.timestamps
    end
    add_index :host_managers, [ :user_id, :host_id ], unique: true
    add_index :host_managers, [ :host_id, :user_id ]
  end

  def down
    drop_table :host_managers
    execute "UPDATE users SET title = 3 WHERE title = 4"
  end
end
