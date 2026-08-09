module Avatarable
  extend ActiveSupport::Concern

  included do
    has_one_attached :photo do |attachable|
      attachable.variant :tiny,  resize_to_limit: [  40,  40 ], format: "webp", saver: { quality: 88 }, preprocessed: true
      attachable.variant :small, resize_to_limit: [ 100, 100 ], format: "webp", saver: { quality: 88 }, preprocessed: true
      attachable.variant :card,  resize_to_fill:  [ 200, 200 ], format: "webp", saver: { quality: 88 }, preprocessed: true
    end
  end
end
