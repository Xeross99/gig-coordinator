# Teksty interfejsu używane w więcej niż jednym miejscu. Wcześniej żyły
# w config/locales/pl.yml — aplikacja jest jednojęzyczna, więc i18n dawało
# tylko warstwę pośrednią: literówka w kluczu cicho renderowała
# "translation missing", a tekstu nie dało się znaleźć gruntownym grepem.
# Jako stałe: literówka to NameError przy starcie, a każde użycie jest
# odnajdywalne po nazwie stałej.
#
# Teksty użyte w JEDNYM miejscu nie trafiają tutaj — stoją wprost tam,
# gdzie się renderują. W i18n zostały wyłącznie lookupy sterowane danymi
# oraz formaty date/time/number, z których korzysta Rails. Lookupy po
# wartościach enuma nie idą tutaj — leżą jako hashe przy swoich enumach
# (User::TITLE_LABELS, User::PLAYER_CARD_LABELS, EventsHelper#host_history_verb).
module Copy
  module Admin
    module Events
      DELETE = "Usuń zlecenie".freeze
      DELETE_CONFIRM = "Na pewno usunąć „%{name}\"? Wszystkie zapisy, podwózki i wiadomości znikną.".freeze
      EDIT = "Edytuj zlecenie".freeze
      TOOLS = "Zarządzanie zleceniem".freeze
    end

    module Hosts
      EDIT_TITLE = "Edytuj gospodarza".freeze
      NEW_TITLE = "Dodaj gospodarza".freeze
    end

    module Users
      EDIT_TITLE = "Edytuj pracownika".freeze
      NEW_TITLE = "Dodaj pracownika".freeze
    end
  end

  module Auth
    CODE_PROMPT = "Wpisz kod z e-maila".freeze
    LOGIN_TITLE = "Zaloguj się".freeze
    LOGOUT = "Wyloguj".freeze
  end

  module EventCampaigns
    CAPACITY_HINT = "Ile osób ma być w głównym składzie serii. Mistrze Pióra dostaną automatyczne rezerwacje aż skład się zapełni.".freeze
    CAPACITY_LABEL = "Liczba miejsc w głównym składzie".freeze
    CREATED = "Seria zleceń utworzona.".freeze
    EDIT_CAMPAIGN = "Edytuj serię".freeze
    INDEX_TITLE = "Serie zleceń".freeze
    NAME_LABEL = "Nazwa serii".freeze
    NEW_CAMPAIGN = "Nowa seria".freeze
    SUB_EVENTS_HEADING = "Terminy".freeze
  end

  module Events
    ACCEPT = "Akceptuję".freeze
    CANCEL = "Anuluj".freeze
    CONFIRMED_BADGE = "Potwierdzony".freeze
    CONFIRMED_COUNT = "Potwierdzeni".freeze
    EDIT_EVENT = "Edytuj zlecenie".freeze
    HOST = "Gospodarz".freeze
    HOST_LABEL = "W imieniu gospodarza".freeze
    MANAGE_FORBIDDEN = "Nie masz uprawnień do zarządzania tym zleceniem.".freeze
    NEW_EVENT = "Zaplanuj zlecenie".freeze
    NEW_EVENT_FORBIDDEN = "Nie masz uprawnień do planowania zleceń.".freeze
    OPEN_IN_MAPS = "Otwórz w Google Maps".freeze
    PAY_PER_PERSON = "Zapłata za osobę".freeze
    SAVE_CHANGES = "Zapisz zmiany".freeze
    UPCOMING = "Nadchodzące".freeze
    WAITLIST_ACCEPT = "Dołącz na listę rezerwową".freeze
    WAITLIST_BADGE = "Lista rezerwowa".freeze
    WAITLIST_COUNT = "Rezerwa".freeze
  end

  module HostPanel
    MY_EVENTS = "Moje zlecenia".freeze
    NEW_EVENT = "Nowe zlecenie".freeze
    PROFILE = "Mój profil".freeze
    TITLE = "Panel gospodarza".freeze

    module History
      EMPTY = "Nic się jeszcze nie zadziało.".freeze
      HEADING = "Historia zapisów".freeze
    end
  end

  module Participations
    BLOCKED = "Masz blokadę u tego gospodarza - nie możesz zapisać się na to zlecenie.".freeze
    BLOCKED_BADGE = "Blokada u gospodarza".freeze
    ZOLTODZIOB_BADGE = "Tylko podgląd".freeze
    ZOLTODZIOB_VIEW_ONLY = "Jako Żółtodziób przeglądasz zlecenia, ale nie zapisujesz się na nie. Po awansie odzyskasz przycisk „Akceptuję”.".freeze
  end

  module SwapProposals
    CONDITIONS_CHANGED = "Warunki wymiany się zmieniły. Spróbuj ponownie.".freeze
    NOT_YOUR_PROPOSAL = "To nie jest Twoja propozycja wymiany.".freeze
    PROPOSE_SHORT = "Wymiana".freeze
  end

  module Users
    DISABLED_BADGE = "Konto wyłączone".freeze
    MANAGES = "Zarządza".freeze
    PREMIUM_BADGE = "Dla wspierających".freeze
  end
end
