defmodule OpenAperture.Deployer.GitHub.Test do
  use ExUnit.Case

  alias OpenAperture.Deployer.GitHub

  test "resolves github repo url" do
    repo_url = GitHub.resolve_repo_url("cool_org/cool_repo")
    assert Regex.match?(~r/https:\/\/(\S)*\/cool_org\/cool_repo.git/, repo_url)
  end

  test "creates a genserver" do
    options = %{
      output_dir: "test_output_dir",
      repo_url: GitHub.resolve_repo_url("cool_org/cool_repo"),
      branch: "test"
    }

    {atom, _} = GitHub.create(options)
    assert atom == :ok
  end

  defmodule WithAgentCreated do
    @options %{
      output_dir: "test_output_dir",
      repo_url: GitHub.resolve_repo_url("cool_org/cool_repo"),
      branch: "test"
    }

    use ExUnit.Case

    setup do
      # this will set the context for each test to the GitHub pid
      {_, pid} = GitHub.create(@options)
      {:ok, pid: pid}
    end

    test "get_options", context do
      assert GitHub.get_options(context[:pid]) == @options
    end

    test "get_options for nil", context do
      assert GitHub.get_options(nil) == nil
    end

    test "clone -- success", context do
      :meck.new(System, [:unstick])
      try do
        :meck.expect(System, :cmd, fn command, args, opts ->
          assert command == "/bin/bash"
          assert Regex.match?(~r/git clone #{@options[:repo_url]} #{@options[:output_dir]}/, Enum.at(args, 1))
          {"cool test message", 0}
        end)
        assert GitHub.clone(context[:pid]) == :ok
      after
        :meck.unload(System)
      end
    end

    test "clone -- invalid agent", context do
      assert GitHub.clone(nil) == {:error, "invalid github agent!"}
    end

    test "clone --error", context do
      :meck.new(System, [:unstick])
      try do

        :meck.expect(System, :cmd, fn _, _, _ -> {"oh no!", 1} end)
        result = GitHub.clone(context[:pid])
        assert elem(result, 0) == :error
        assert elem(result, 1) != nil
      after
        :meck.unload(System)
      end
    end

    test "checkout -- success", context do
      :meck.new(System, [:unstick])
      try do
        :meck.expect(System, :cmd, fn command, args, opts ->
          assert command == "/bin/bash"
          assert Regex.match?(~r/git checkout #{@options[:branch]}/, Enum.at(args, 1))
          {"cool success message", 0}
        end)

        assert GitHub.checkout(context[:pid]) == :ok
      after
        :meck.unload(System)
      end
    end

    test "checkout -- invalid agent", context do
      assert GitHub.checkout(nil) == {:error, "invalid github agent!"}
    end

    test "checkout -- error", context do
      :meck.new(System, [:unstick])
      try do
        :meck.expect(System, :cmd, fn _, _, _ -> {"oh no!", 1} end)

        result = GitHub.checkout(context[:pid])
        assert elem(result, 0) == :error
        assert elem(result, 1) != nil
      after
        :meck.unload(System)
      end
    end

    test "add -- success", context do
      filepath = "cool_folder/cool_file"
      :meck.new(System, [:unstick])
      try do
        :meck.expect(System, :cmd, fn command, args, opts ->
          assert command == "/bin/bash"
          assert Regex.match?(~r/git add #{filepath}/, Enum.at(args, 1))
          {"cool success message", 0}
        end)

        assert GitHub.add(context[:pid], filepath) == :ok
      after
        :meck.unload(System)
      end
    end

    test "add -- invalid agent", context do
      assert GitHub.add(nil, "cool file") == {:error, "invalid github agent!"}
    end

    test "add -- error", context do
      filepath = "cool_folder/cool_file"
      :meck.new(System, [:unstick])

      try do
        :meck.expect(System, :cmd, fn _, _, _ -> {"oh no!", 1} end)

        result = GitHub.add(context[:pid], filepath)
        assert elem(result, 0) == :error
        assert elem(result, 1) != nil
      after
        :meck.unload(System)
      end
    end

    test "commit -- success", context do
      message = "cool commit message"
      :meck.new(System, [:unstick])

      try do
        :meck.expect(System, :cmd, fn command, args, opts ->
          assert command == "/bin/bash"
          assert Regex.match?(~r/git commit -m "#{message}"/, Enum.at(args, 1))
          {"cool success message", 0}
        end)

        assert GitHub.commit(context[:pid], message) == :ok
      after
        :meck.unload(System)
      end
    end

    test "commit -- invalid agent", context do
      assert GitHub.commit(nil, "cool message") == {:error, "invalid github agent!"}
    end

    test "commit -- failure", context do
      message = "cool commit message"
      :meck.new(System, [:unstick])

      try do
        :meck.expect(System, :cmd, fn _, _, _ -> {"oh no!", 1} end)

        result = GitHub.commit(context[:pid], message)
        assert elem(result, 0) == :error
        assert elem(result, 1) != nil
      after
        :meck.unload(System)
      end
    end

    test "push -- success", context do
      :meck.new(System, [:unstick])

      try do
        :meck.expect(System, :cmd, fn command, args, opts ->
          assert command == "/bin/bash"
          assert Regex.match?(~r/git push/, Enum.at(args, 1))
          {"cool success message", 0}
        end)

        assert GitHub.push(context[:pid]) == :ok
      after
        :meck.unload(System)
      end
    end

    test "push -- invalid agent", context do
      assert GitHub.push(nil) == {:error, "invalid github agent!"}
    end

    test "push -- error", context do
      :meck.new(System, [:unstick])

      try do
        :meck.expect(System, :cmd, fn _, _, _ -> {"oh no!", 1} end)

        result = GitHub.push(context[:pid])
        assert elem(result, 0) == :error
        assert elem(result, 1) != nil
      after
        :meck.unload(System)
      end
    end
  end

  #===========================
  # get_project_name tests

  test "get_project_name - success", context do
    assert GitHub.get_project_name("https://github.com/Perceptive-Cloud/myapp") == "myapp"
  end

  test "get_project_name - suffix", context do
    assert GitHub.get_project_name("https://github.com/Perceptive-Cloud/myapp.git") == "myapp.git"
  end

  #===========================
  # add_all tests

  test "add_all -- success", context do
    filepath = "cool_folder"
    :meck.new(System, [:unstick, :passthrough])

    try do
      :meck.expect(System, :cmd, fn command, args, opts ->
        assert command == "/bin/bash"
        assert Regex.match?(~r/git add -A #{filepath}/, Enum.at(args, 1))
        {"cool success message", 0}
      end)

      options = %{
        output_dir: "test_output_dir",
        repo_url: GitHub.resolve_repo_url("cool_org/cool_repo"),
        branch: "test"
      }
      {_, pid} = GitHub.create(options)
      assert GitHub.add_all(pid, filepath) == :ok
    after
      :meck.unload(System)
    end
  end

  test "add_all -- invalid agent", context do
    assert GitHub.add_all(nil, "cool_folder") == {:error, "invalid github agent!"}
  end

  test "add_all -- error", context do
    filepath = "cool_folder"
    :meck.new(System, [:unstick, :passthrough])

    try do
      :meck.expect(System, :cmd, fn _, _, _ -> {"oh no!", 1} end)

      options = %{
        output_dir: "test_output_dir",
        repo_url: GitHub.resolve_repo_url("cool_org/cool_repo"),
        branch: "test"
      }

      {_, pid} = GitHub.create(options)
      result = GitHub.add_all(pid, filepath)
      assert elem(result, 0) == :error
      assert elem(result, 1) != nil
    after
      :meck.unload(System)
    end
  end
end
