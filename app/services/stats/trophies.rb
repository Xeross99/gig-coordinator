# Katalog trofeów „społeczności" — śmieszne kategorie dobrane tak, żeby
# zwycięzcy naturalnie się rozjeżdżali (różne wektory: liczba, czas, pieniądze,
# szybkość, role carpoolowe). Lista jest źródłem prawdy o kolejności + treści;
# `StatsService.compute` przelatuje ją po kolei, a widok renderuje wynik 1:1.
#
# To jest plik z TREŚCIĄ, nie z logiką — zmienia się, gdy ktoś wymyśli nowe
# trofeum, a nie gdy poprawiasz zapytanie. Zapytania siedzą w `StatsService`
# pod `compute_<key>`; nie przenoś ich tutaj, bo wtedy katalog znów przestanie
# być czytelną listą.
#
# Dodanie nowego trofeum: dopisz wpis z `key:` + zaimplementuj `compute_<key>`
# w `StatsService`, zwracającą posortowaną (najlepszy pierwszy) listę do 3 par
# `[user_id, sformatowana_wartość]` — miejsce 1 renderuje się jako zwycięzca,
# miejsca 2-3 jako mniejsze wiersze pod nim. Pusta lista = brak zwycięzcy.
module Stats
  module Trophies
    ALL = [
      {
        key:         :hours,
        emoji:       "🏃",
        title:       "Maratończyk",
        description: "Najwięcej godzin spędzonych w kurniku. Wytrzymałość konia pociągowego.",
        unit:        "h"
      },
      {
        key:         :waitlist,
        emoji:       "🪑",
        title:       "Wieczna Rezerwa",
        description: "Najczęściej ląduje na liście rezerwowej.",
        unit:        "razy"
      },
      {
        key:         :flake,
        emoji:       "🥀",
        title:       "Niesłowny",
        description: "Najczęściej wycofuje zapis po potwierdzeniu. Dziś tak, jutro nie.",
        unit:        "wycofań"
      },
      {
        key:         :reliable,
        emoji:       "🎯",
        title:       "Niezawodny",
        description: "Najrzadziej wycofuje zapis. Jak się wpisał, to przyjdzie.",
        unit:        "% wycofań"
      },
      {
        key:         :last_minute,
        emoji:       "💨",
        title:       "Kurzy Tchórz",
        description: "Uciekł z głównej listy najbliżej startu zlecenia. Coś musiało wypaść.",
        unit:        "przed startem"
      },
      {
        key:         :organizer,
        emoji:       "📋",
        title:       "Organizator",
        description: "Stworzył najwięcej zleceń. Bez niego nikt by nie wiedział kiedy idziemy.",
        unit:        "zleceń"
      },
      {
        key:         :globetrotter,
        emoji:       "🧭",
        title:       "Obieżyświat",
        description: "Łapał u największej liczby gospodarzy. Wszędzie go znają.",
        unit:        "gospodarzy"
      },
      {
        key:         :passenger,
        emoji:       "🚗",
        title:       "Pasażer na Gapę",
        description: "Najczęściej dawał się podwieźć. Auto samo się nie pojawi.",
        unit:        "razy"
      },
      {
        key:         :promoted,
        emoji:       "⬆️",
        title:       "Awansowany",
        description: "Najczęściej skakał z rezerwy do głównej listy. Cierpliwość się opłaca.",
        unit:        "awansów"
      },
      {
        key:         :negotiator,
        emoji:       "🤝",
        title:       "Negocjator",
        description: "Najczęściej proponuje wymiany. Zawsze znajdzie sposób, żeby wskoczyć.",
        unit:        "propozycji"
      },
      {
        key:         :swapper,
        emoji:       "♻️",
        title:       "Rekin Wymian",
        description: "Najczęściej wchodził na główną listę przez wymianę. Handel kwitnie.",
        unit:        "wymian"
      },
      {
        key:         :patient,
        emoji:       "🛋️",
        title:       "Wytrwały Rezerwista",
        description: "Najwięcej czasu przesiedział łącznie na rezerwie. Cierpliwość z żelaza.",
        unit:        "dni na rezerwie"
      },
      {
        key:         :weekend,
        emoji:       "🍻",
        title:       "Weekendowy Wojownik",
        description: "Najwięcej zleceń w soboty i niedziele. Weekend to też praca.",
        unit:        "zleceń"
      },
      {
        key:         :quick_undo,
        emoji:       "🔄",
        title:       "Klikam i Cofam",
        description: "Najkrótszy odstęp między zapisem a wycofaniem. Zmienił zdanie zanim powiadomienie zdążyło wibrować.",
        unit:        nil
      },
      {
        key:         :hitchhiker,
        emoji:       "📞",
        title:       "Sygnalista",
        description: "Najwięcej zapytań o podwózkę wysłanych do kierowców. Przewieziony lub nie — pyta zawsze.",
        unit:        "zapytań"
      },
      {
        key:         :ghoster,
        emoji:       "👻",
        title:       "Mistrz Pauzy",
        description: "Najwięcej rezerwacji, które wygasły bez odpowiedzi. Mistrz Pióra w trybie offline.",
        unit:        "wygaśnięć"
      },
      {
        key:         :first_lady,
        emoji:       "🥇",
        title:       "Pierwsza Łapa",
        description: "Najczęściej pierwszy na potwierdzonej liście. Kto nie pierwszy, ten ostatni.",
        unit:        "razy"
      },
      {
        key:         :last_man_in,
        emoji:       "🚪",
        title:       "Ostatni Sprawiedliwy",
        description: "Najczęściej zajmował ostatnie miejsce na głównej liście. Drzwi zamknęli mu tuż za plecami.",
        unit:        "razy"
      },
      {
        key:         :rookie,
        emoji:       "🆕",
        title:       "Świeżynka",
        description: "Najświeższy nabytek wśród pracowników. Witamy w klubie.",
        unit:        "rejestracja"
      },
      {
        key:         :unlucky,
        emoji:       "🎟️",
        title:       "Pechowiec",
        description: "Najwyższy procent zapisów lądujących na liście rezerwowej. Drugi rząd to jego dom.",
        unit:        "% rezerwy"
      },
      {
        key:         :driver,
        emoji:       "🚐",
        title:       "Człowiek-Bus",
        description: "Przewiózł najwięcej pasażerów. Wozi pół wsi.",
        unit:        "pasażerów"
      },
      {
        key:         :quiet_hero,
        emoji:       "🤫",
        title:       "Cichy Bohater",
        description: "Żadnego pucharu na półce, a robota zrobiona. Ranking wyłącznie dla nieodznaczonych.",
        unit:        "zleceń"
      }
    ].freeze
  end
end
