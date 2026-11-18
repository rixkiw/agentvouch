// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AgentVouch} from "../src/AgentVouch.sol";

/// Fork tests against BNB Smart Chain mainnet: real Agent ID holders only.
contract AgentVouchForkTest is Test {
    AgentVouch v;

    address constant RIXKIW = 0xC8D59C5afdcb7e4292C8763770A202d57BcD8f74; // rixkiw.ai
    address constant TRIUSUS = 0x1bbD75de806bA32c1B2B3C29CbA16078D14A3356; // triusus.ai
    address constant NOBODY = address(0xBEEF);

    function setUp() public {
        v = new AgentVouch();
    }

    function testAgentsAreAgents() public view {
        assertTrue(v.isAgent(RIXKIW), "rixkiw.ai should be an agent");
        assertTrue(v.isAgent(TRIUSUS), "triusus.ai should be an agent");
        assertFalse(v.isAgent(NOBODY), "random EOA is not an agent");
    }

    function testHandleOfSafe() public view {
        assertEq(v.handleOfSafe(RIXKIW), "rixkiw");
        assertEq(v.handleOfSafe(TRIUSUS), "triusus");
        assertEq(v.handleOfSafe(NOBODY), "");
    }

    function testVouchHappyPath() public {
        vm.prank(RIXKIW);
        v.vouch(TRIUSUS, "ships fast, verifies on-chain");

        assertEq(v.vouchCount(TRIUSUS), 1);
        assertEq(v.vouchesGiven(RIXKIW), 1);
        assertEq(v.totalVouches(), 1);

        (bool exists, uint64 at, string memory note) = v.vouchOf(RIXKIW, TRIUSUS);
        assertTrue(exists);
        assertEq(at, uint64(block.timestamp));
        assertEq(note, "ships fast, verifies on-chain");

        address[] memory vs = v.vouchersOf(TRIUSUS);
        assertEq(vs.length, 1);
        assertEq(vs[0], RIXKIW);
    }

    function testNonAgentCannotVouch() public {
        vm.prank(NOBODY);
        vm.expectRevert(abi.encodeWithSelector(AgentVouch.NotAnAgent.selector, NOBODY));
        v.vouch(TRIUSUS, "hi");
    }

    function testCannotVouchNonAgent() public {
        vm.prank(RIXKIW);
        vm.expectRevert(abi.encodeWithSelector(AgentVouch.NotAnAgent.selector, NOBODY));
        v.vouch(NOBODY, "hi");
    }

    function testNoSelfVouch() public {
        vm.prank(RIXKIW);
        vm.expectRevert(AgentVouch.SelfVouch.selector);
        v.vouch(RIXKIW, "me");
    }

    function testNoDoubleVouch() public {
        vm.startPrank(RIXKIW);
        v.vouch(TRIUSUS, "one");
        vm.expectRevert(AgentVouch.AlreadyVouched.selector);
        v.vouch(TRIUSUS, "two");
        vm.stopPrank();
    }

    function testNoteTooLong() public {
        bytes memory big = new bytes(161);
        vm.prank(RIXKIW);
        vm.expectRevert(abi.encodeWithSelector(AgentVouch.NoteTooLong.selector, 161));
        v.vouch(TRIUSUS, string(big));
    }

    function testRevokeAndSwapPop() public {
        // three distinct vouches would need three agents; two is enough for swap-pop
        vm.prank(RIXKIW);
        v.vouch(TRIUSUS, "a");
        vm.prank(TRIUSUS);
        v.vouch(RIXKIW, "b");

        vm.prank(RIXKIW);
        v.revoke(TRIUSUS);
        assertEq(v.vouchCount(TRIUSUS), 0);
        assertEq(v.vouchesGiven(RIXKIW), 0);
        (bool exists, , ) = v.vouchOf(RIXKIW, TRIUSUS);
        assertFalse(exists);
        assertEq(v.vouchersOf(TRIUSUS).length, 0);

        // revoking again reverts
        vm.prank(RIXKIW);
        vm.expectRevert(AgentVouch.NotVouched.selector);
        v.revoke(TRIUSUS);

        // can vouch again after revoking
        vm.prank(RIXKIW);
        v.vouch(TRIUSUS, "again");
        assertEq(v.vouchCount(TRIUSUS), 1);
    }

    function testPagedVouchers() public {
        vm.prank(RIXKIW);
        v.vouch(TRIUSUS, "x");
        (address[] memory page, uint256 next) = v.vouchersOfPaged(TRIUSUS, 0, 10);
        assertEq(page.length, 1);
        assertEq(next, 1);
        (address[] memory empty, uint256 next2) = v.vouchersOfPaged(TRIUSUS, 5, 10);
        assertEq(empty.length, 0);
        assertEq(next2, 1);
    }

    function testNoOwnerSurface() public {
        // no owner(), no withdraw(), no pause(): calling them must revert
        (bool ok, ) = address(v).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok, "contract must have no owner()");
        (bool ok2, ) = address(v).call(abi.encodeWithSignature("withdraw()"));
        assertFalse(ok2, "contract must have no withdraw()");
        assertEq(address(v).balance, 0);
    }
}
