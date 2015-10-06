defmodule OpenAperture.Deployer.Mixfile do
  use Mix.Project

  def project do
    [app: :openaperture_deployer,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps]
  end

  def application do
    [
      applications: [
        :logger,
        :amqp,
        :fleet_api,
        :openaperture_fleet,
        :openaperture_messaging, 
        :openaperture_manager_api, 
        :openaperture_overseer_api,
        :openaperture_workflow_orchestrator_api
      ],
      mod: {OpenAperture.Deployer, []}
    ]
  end

  defp deps do
    [
      {:ex_doc, github: "elixir-lang/ex_doc", only: [:test], override: true},
      {:earmark, github: "pragdave/earmark", tag: "v0.1.8", only: [:test], override: true},    
      
      {:poison, "~>1.4.0", override: true},
      {:openaperture_messaging, git: "https://github.com/OpenAperture/messaging.git", ref: "380ce611a038dd8f7afb4fa7f660aeac06475af0", override: true},
      {:openaperture_manager_api, git: "https://github.com/OpenAperture/manager_api.git", ref: "dc06f0a484410e7707dab8e96807d54a564557ed", override: true},
      {:openaperture_overseer_api, git: "https://github.com/OpenAperture/overseer_api.git", ref: "67e1ec93cf1e12e5b0e86165f33ede703a886092", override: true},
      {:openaperture_fleet, git: "https://github.com/OpenAperture/fleet.git", ref: "9fa880eef5aa23bf89e3f121df04fdc542c74c73", override: true},
      {:openaperture_workflow_orchestrator_api, git: "https://github.com/OpenAperture/workflow_orchestrator_api.git", ref: "4e56be62204b4ac3f05facb518b54f19eeba0c70", override: true},
      {:timex, "~> 0.13.3", override: true},
      {:fleet_api, "~> 0.0.15", override: true},

      #test dependencies
      {:exvcr, github: "parroty/exvcr", only: :test},
      {:meck, "0.8.3", override: true},
    ]
  end
end
