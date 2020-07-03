Rails.application.routes.draw do
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  root to: 'statuses#home'

  get '/login', to: 'sessions#new'
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'
  get '/status', to: 'statuses#home'
  post '/update_status/:id', to: 'statuses#update_status', as: 'update_status'
  post '/extend_status/:id', to: 'statuses#extend_status', as: 'extend_status'
  post '/end_use_status/:id', to: 'statuses#end_use_status', as: 'end_use_status'

  namespace :admin do
    resources :users
    resources :items
  end
end
