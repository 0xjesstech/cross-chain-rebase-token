//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {Register} from "@chainlink-local/src/ccip/Register.sol";
import {
    RegistryModuleOwnerCustom
} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {CCIPLocalSimulatorFork} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";
import {TokenAdminRegistry} from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@chainlink/contracts-ccip/contracts/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    address OWNER = makeAddr("OWNER");
    address USER = makeAddr("USER");

    uint256 SEND_VALUE = 1e5;
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken private sepoliaToken;
    RebaseToken private arbSepoliaToken;
    Vault private vault;
    RebaseTokenPool private sepoliaTokenPool;
    RebaseTokenPool private arbSepoliaTokenPool;

    // Store addresses explicitly to avoid cross-fork issues
    address private sepoliaTokenAddress;
    address private arbSepoliaTokenAddress;
    address private sepoliaTokenPoolAddress;
    address private arbSepoliaTokenPoolAddress;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Deploy and configure on Sepolia
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(OWNER);
        sepoliaToken = new RebaseToken();
        sepoliaTokenAddress = address(sepoliaToken);
        vault = new Vault(IRebaseToken(sepoliaTokenAddress));
        sepoliaTokenPool = new RebaseTokenPool(
            IERC20(sepoliaTokenAddress),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        sepoliaTokenPoolAddress = address(sepoliaTokenPool);
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(sepoliaTokenPoolAddress);
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(sepoliaToken), address(sepoliaTokenPool));
        vm.stopPrank();

        // Deploy and configure on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(OWNER);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaTokenAddress = address(arbSepoliaToken);
        arbSepoliaTokenPool = new RebaseTokenPool(
            IERC20(arbSepoliaTokenAddress),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaTokenPoolAddress = address(arbSepoliaTokenPool);
        arbSepoliaToken.grantMintAndBurnRole(arbSepoliaTokenPoolAddress);
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(arbSepoliaToken), address(arbSepoliaTokenPool));

        vm.stopPrank();
        configureTokenPool(
            sepoliaFork,
            sepoliaTokenPoolAddress,
            uint64(arbSepoliaNetworkDetails.chainSelector),
            arbSepoliaTokenPoolAddress,
            arbSepoliaTokenAddress
        );

        configureTokenPool(
            arbSepoliaFork,
            arbSepoliaTokenPoolAddress,
            uint64(sepoliaNetworkDetails.chainSelector),
            sepoliaTokenPoolAddress,
            sepoliaTokenAddress
        );
    }

    function configureTokenPool(
        uint256 forkId,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress
    ) public {
        vm.selectFork(forkId);
        vm.prank(OWNER);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainsToAdd);
    }

    function _buildCCIPMessage(address token, uint256 amount, address linkAddress)
        internal
        view
        returns (Client.EVM2AnyMessage memory)
    {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: token, amount: amount});
        return Client.EVM2AnyMessage({
            receiver: abi.encode(USER),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 1000000}))
        });
    }

    function _sendCCIPMessage(
        Client.EVM2AnyMessage memory message,
        Register.NetworkDetails memory localNetworkDetails,
        uint64 remoteChainSelector,
        uint256 amountToBridge
    ) internal {
        uint256 fee = IRouterClient(localNetworkDetails.routerAddress).getFee(remoteChainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(USER, fee);
        vm.prank(USER);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        vm.prank(USER);
        IERC20(message.tokenAmounts[0].token).approve(localNetworkDetails.routerAddress, amountToBridge);
        vm.prank(USER);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteChainSelector, message);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);

        Client.EVM2AnyMessage memory message =
            _buildCCIPMessage(address(localToken), amountToBridge, localNetworkDetails.linkAddress);

        uint256 localBalanceBefore = localToken.balanceOf(USER);
        uint256 localUserInterestRate = localToken.getUserInterestRate(USER);

        _sendCCIPMessage(message, localNetworkDetails, remoteNetworkDetails.chainSelector, amountToBridge);

        assertEq(localToken.balanceOf(USER), localBalanceBefore - amountToBridge);

        // Get balance on remote before routing
        vm.selectFork(remoteFork);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(USER);

        // Switch back to source fork to route the message
        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        // Check balance on remote after routing
        vm.selectFork(remoteFork);
        assertGe(remoteToken.balanceOf(USER), remoteBalanceBefore + amountToBridge);
        assertEq(remoteToken.getUserInterestRate(USER), localUserInterestRate);
    }

    function testBridgeAllTokens() public {
        vm.selectFork(sepoliaFork);
        vm.deal(USER, SEND_VALUE);
        vm.startPrank(USER);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        vm.stopPrank();

        // Assert initial state on Sepolia
        assertEq(sepoliaToken.balanceOf(USER), SEND_VALUE);
        uint256 initialInterestRate = sepoliaToken.getUserInterestRate(USER);
        assertGt(initialInterestRate, 0, "User should have an interest rate after deposit");

        // Assert initial state on Arbitrum (should have no tokens)
        vm.selectFork(arbSepoliaFork);
        assertEq(arbSepoliaToken.balanceOf(USER), 0, "User should have no tokens on Arbitrum before bridging");

        // Bridge tokens from Sepolia to Arbitrum
        vm.selectFork(sepoliaFork);
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );

        // Assert state after bridging - Sepolia should have 0 tokens
        vm.selectFork(sepoliaFork);
        assertEq(sepoliaToken.balanceOf(USER), 0, "User should have no tokens on Sepolia after bridging");

        // Assert state after bridging - Arbitrum should have the tokens with same interest rate
        vm.selectFork(arbSepoliaFork);
        assertGe(arbSepoliaToken.balanceOf(USER), SEND_VALUE, "User should have tokens on Arbitrum after bridging");
        assertEq(
            arbSepoliaToken.getUserInterestRate(USER),
            initialInterestRate,
            "Interest rate should be preserved across chains"
        );

        // Warp time and check that interest accrues on Arbitrum
        uint256 balanceBeforeWarp = arbSepoliaToken.balanceOf(USER);
        vm.warp(block.timestamp + 1 hours);
        uint256 balanceAfterWarp = arbSepoliaToken.balanceOf(USER);
        assertGt(balanceAfterWarp, balanceBeforeWarp, "Balance should increase due to interest accrual");
    }
}
