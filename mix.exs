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
      {:ex_doc, github: "elixir-lang/ex_doc", only: [:test]},
      {:markdown, github: "devinus/markdown", only: [:test]},    
      
      {:openaperture_messaging, git: "https://github.com/OpenAperture/messaging.git",ref: "11061d019bab15c4b43425f7cdb50899eef05b45", override: true},
      {:openaperture_manager_api, git: "https://github.com/OpenAperture/manager_api.git",ref: "ae629a4127acceac8a9791c85e5a0d3b67d1ad16", override: true},      
      {:openaperture_fleet, git: "https://github.com/OpenAperture/fleet.git", ref: "7aa864eeb3876b476c89d58c56364cbb0fa2fb08", override: true},
      {:openaperture_workflow_orchestrator_api, git: "https://github.com/OpenAperture/workflow_orchestrator_api.git", ref: "488832b216a1a139a6c58d788083cf5054b3dbe8", override: true},        
      {:openaperture_overseer_api, git: "https://github.com/OpenAperture/overseer_api.git", ref: "d2cd242af35e6b5c211a7d43a016e825a65e2dda", override: true},
      {:timex, "~> 0.12.9"},
      {:fleet_api, "~> 0.0.4"},

      #test dependencies
      {:exvcr, github: "parroty/exvcr", only: :test},
      {:meck, "0.8.2", only: :test}
    ]
  end
end
