Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  root to: 'statuses#home'

  get '/login', to: 'sessions#new'
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'
  get '/status', to: 'statuses#home'
  get '/history', to: 'usage_histories#index', as: 'usage_histories'
  post '/status/deadline_preview', to: 'statuses#deadline_preview', as: 'deadline_preview'
  post '/update_status/:id', to: 'statuses#update_status', as: 'update_status'
  post '/extend_status/:id', to: 'statuses#extend_status', as: 'extend_status'
  post '/end_use_status/:id', to: 'statuses#end_use_status', as: 'end_use_status'

  namespace :admin do
    resources :users
    resources :items
  end
end
