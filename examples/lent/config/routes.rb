# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

Rails.application.routes.draw do
  resources :loans, except: %i[index show] do
    patch :return, on: :member
  end
  root "loans#index"
end
