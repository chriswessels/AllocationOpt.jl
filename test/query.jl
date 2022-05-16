using GraphQLClient

@testset "query" begin
    @testset "verify_ipfshashes" begin
        # Should fail due to bad prefix
        hashes = [
            "QmauYgPmss6CEZXtaRvvGW2oiyLqxpoCkWNCTmFPVTFDfk",
            "AmauYgPmss6CEZXtaRvvGW2oiyLqxpoCkWNCTmFPVTFDfk",
        ]
        @test !verify_ipfshashes(hashes)

        # Should pass for good hashes
        hashes = [
            "QmauYgPmss6CEZXtaRvvGW2oiyLqxpoCkWNCTmFPVTFDfk",
            "QmhiYgPmss6CEZXtaRvvGW2oiyLqxpoCkWNCTmFPVTFDfk",
        ]
        @test verify_ipfshashes(hashes)

        # Should fail for empty strings
        hashes = [
            "QmauYgPmss6CEZXtaRvvGW2oiyLqxpoCkWNCTmFPVTFDfk",
            "QmhiYgPmss6CEZXtaRvvGW2oiyLqxpoCkWNCTmFPVTFDfk",
            "",
        ]
        @test !verify_ipfshashes(hashes)

        # Should pass for empty lists
        hashes = String[]
        @test verify_ipfshashes(hashes)
    end

    @testset "ipfshash_in" begin
        # Should handle nominal input
        whitelist = ["a", "b", "c"]
        pinnedlist = ["d"]
        output = ipfshash_in(whitelist, pinnedlist)
        @test output == ["a", "b", "c", "d"]

        # Should handle empty inputs
        whitelist = String[]
        pinnedlist = String[]
        output = ipfshash_in(whitelist, pinnedlist)
        @test output == []

        # Should handle overlapping input
        whitelist = ["a", "b", "c"]
        pinnedlist = ["c", "d"]
        output = ipfshash_in(whitelist, pinnedlist)
        @test output == ["a", "b", "c", "d"]
    end

    @testset "ipfshash_not_in" begin
        # Should handle nominal input
        blacklist = ["a", "b", "c"]
        frozenlist = ["d"]
        output = ipfshash_not_in(blacklist, frozenlist)
        @test output == ["a", "b", "c", "d"]

        # Should handle empty inputs
        blacklist = String[]
        frozenlist = String[]
        output = ipfshash_not_in(blacklist, frozenlist)
        @test output == []

        # Should handle overlapping input
        blacklist = ["a", "b", "c"]
        frozenlist = ["c", "d"]
        output = ipfshash_not_in(blacklist, frozenlist)
        @test output == ["a", "b", "c", "d"]
    end

    @testset "snapshot ipfs filtering subgraph deployments" begin
        client = gql_client()
        all_hashes = [
            deployment["ipfsHash"] for deployment in
            query(client, "subgraphDeployments"; query_args=Dict("first" => 1000, "where" => Dict("signalledTokens_gte" => "1000000000000000000000")), output_fields="ipfsHash").data["subgraphDeployments"]
        ]

        # Should return the one whitelisted subgraph
        repo, network = snapshot(client, [all_hashes[1]], String[])
        @test length(repo.subgraphs) == 1
        @test repo.subgraphs[1].ipfshash == all_hashes[1]

        # Should return the one subgraph not blacklisted
        repo, network = snapshot(client, String[], all_hashes[2:end])
        @test length(repo.subgraphs) == 1
        @test repo.subgraphs[1].ipfshash == all_hashes[1]

        # Should return all subgraphs
        repo, network = snapshot(client, String[], String[])
        @test length(repo.subgraphs) == length(all_hashes)

        # Should return subgraphs in whitelist that aren't in blacklist
        repo, network = snapshot(client, all_hashes, all_hashes[2:end])
        @test length(repo.subgraphs) == 1
        @test repo.subgraphs[1].ipfshash == all_hashes[1]
    end

    @testset "snapshot ipfs filtering indexer allocations" begin
        client = gql_client()
        all_hashes = [
            deployment["ipfsHash"] for deployment in
            query(client, "subgraphDeployments"; query_args=Dict("first" => 1000, "where" => Dict("signalledTokens_gte" => "1000000000000000000000")), output_fields="ipfsHash").data["subgraphDeployments"]
        ]

        # Should have only one possible subgraph to allocate to
        repo, network = snapshot(client, [all_hashes[1]], String[])
        all_allocations = unique([
            a -> a.ipfshash for indexer in repo.indexers for a in indexer.allocations
        ])
        @test length(all_allocations) == 1

        # Should have no allocations
        repo, network = snapshot(client, String[], all_hashes)
        @test sum(map(x -> length(x.allocations), repo.indexers)) == 0
    end

    @testset "frozen stake" begin
        # calculate the stake constraint for indexer
        client = gql_client()
        subgraphs = query_subgraphs(client, String[], String[])
        indexers = query_indexers(client, subgraphs)
        indexer = indexers[findfirst(i -> length(i.allocations) > 0, indexers)]
        id = indexer.id
        freezed_allocation = indexer.allocations[1]

        @test frozen_stake(client, id, String[]) == 0.0
        @test (frozen_stake(client, id, String[])) <
            frozen_stake(client, id, [freezed_allocation.ipfshash])
    end
end
