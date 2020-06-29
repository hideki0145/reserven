Rails.application.routes.draw do
  get 'statuses/home'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  root to: 'statuses#home'

  get '/login', to: 'sessions#new'
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'

  namespace :admin do
    resources :users
  end
end
