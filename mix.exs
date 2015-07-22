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
      {:openaperture_messaging, git: "https://github.com/OpenAperture/messaging.git", ref: "e48c52b98abc86f4404954e7b4c85b090e83c69c", override: true},
      {:openaperture_manager_api, git: "https://github.com/OpenAperture/manager_api.git", ref: "84eedf15d805e6a827b3d62978b5a20244c99094", override: true},
      {:openaperture_overseer_api, git: "https://github.com/OpenAperture/overseer_api.git", ref: "4d65d2295f2730bc74ec695c32fa0d2478158182", override: true},
      {:openaperture_fleet, git: "https://github.com/OpenAperture/fleet.git", ref: "714c52b5258f96e741b57c73577431caa6f480b3", override: true},
      {:openaperture_workflow_orchestrator_api, git: "https://github.com/OpenAperture/workflow_orchestrator_api.git", ref: "c9c4175117f4807fb312637374d8119772913e3e", override: true},
      {:timex, "~> 0.12.9"},
      {:fleet_api, "~> 0.0.14", override: true},

      #test dependencies
      {:exvcr, github: "parroty/exvcr", only: :test},
      {:meck, "0.8.2", only: :test}
    ]
  end
end
