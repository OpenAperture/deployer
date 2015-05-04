defmodule OpenAperture.Deployer.Milestones.DeployTest do
  use   ExUnit.Case

  alias OpenAperture.Deployer.Milestones.Deploy
  alias OpenAperture.Deployer.Request, as: DeployerRequest

  alias OpenAperture.Fleet.EtcdCluster
 
  # ==========================
  # deploy tests

  test "deploy - no accessible hosts" do
    :meck.new(EtcdCluster, [:passthrough])
    :meck.expect(EtcdCluster, :get_host_count, fn _ -> 0 end)

    deployer_request = %DeployerRequest{
      etcd_token: "123abc"
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :step_failed, fn _,_,_ -> deployer_request end)

    returned_request = Deploy.deploy(deployer_request)
    assert returned_request != nil
  after
    :meck.unload(EtcdCluster)
    :meck.unload(DeployerRequest)
  end

  test "deploy - no deployable_units" do
    :meck.new(EtcdCluster, [:passthrough])
    :meck.expect(EtcdCluster, :get_host_count, fn _ -> 3 end)

    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployable_units: []
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :step_failed, fn _,_,_ -> deployer_request end)

    returned_request = Deploy.deploy(deployer_request)
    assert returned_request != nil
  after
    :meck.unload(EtcdCluster)
    :meck.unload(DeployerRequest)
  end  

  test "deploy - success" do
    :meck.new(EtcdCluster, [:passthrough])
    :meck.expect(EtcdCluster, :get_host_count, fn _ -> 3 end)
    :meck.expect(EtcdCluster, :deploy_units, fn _,_,_ -> [] end)
    
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployable_units: [%{}]
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> deployer_request end)

    returned_request = Deploy.deploy(deployer_request)
    assert returned_request != nil
  after
    :meck.unload(EtcdCluster)
    :meck.unload(DeployerRequest)
  end    
end