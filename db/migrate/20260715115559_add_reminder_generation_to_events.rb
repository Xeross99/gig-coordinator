class AddReminderGenerationToEvents < ActiveRecord::Migration[8.1]
  def change
    # add_column nie przebudowuje tabeli, więc jest bezpieczne bez
    # disable_ddl_transaction! (patrz CLAUDE.md o migracjach SQLite).
    add_column :events, :reminder_generation, :integer, default: 0, null: false
  end
end
