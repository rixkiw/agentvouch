// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AgentVouch — reputation layer keyed by Binance Agent ID
/// @notice A public, on-chain vouch graph for Agentic Wallets. Only holders of a
///         Binance Agent ID (the non-transferable ERC-721 `name.ai` issued by the
///         SPACE ID Agent ID contract on BNB Smart Chain) can vouch, and only
///         Agent ID holders can be vouched for. One vouch per (voucher, agent)
///         pair, revocable at any time. Nothing is paid, nothing is minted,
///         nobody can move funds, and there is no owner.
/// @dev The Agent ID address is a compile-time constant, so deployment takes no
///      constructor arguments and there is nothing to misconfigure.
interface IAgentID {
    /// @notice Number of Agent IDs held by `account` (> 0 == holder).
    function balanceOf(address account) external view returns (uint256);

    /// @notice Human handle of `account` (e.g. "rixkiw" for rixkiw.ai).
    /// @dev Reverts for addresses that hold no Agent ID.
    function handleOf(address account) external view returns (string memory);
}

contract AgentVouch {
    /// @notice Binance Agent ID contract on BNB Smart Chain (chain 56).
    address public constant AGENT_ID =
        0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    /// @notice Maximum length of a vouch note, in bytes.
    uint256 public constant MAX_NOTE_BYTES = 160;

    struct Vouch {
        uint64 at;
        string note;
    }

    /// @notice voucher => agent => vouch
    mapping(address => mapping(address => Vouch)) private _vouch;

    /// @notice agent => list of addresses currently vouching for them
    mapping(address => address[]) private _vouchers;

    /// @notice agent => index+1 of a voucher inside _vouchers[agent] (0 == none)
    mapping(address => mapping(address => uint256)) private _voucherIndex;

    /// @notice agent => number of active vouches received
    mapping(address => uint32) public vouchCount;

    /// @notice agent => number of vouches ever cast by this agent
    mapping(address => uint32) public vouchesGiven;

    /// @notice Total number of active vouches in the graph.
    uint32 public totalVouches;

    event Vouched(
        address indexed voucher,
        address indexed agent,
        string note,
        uint64 at
    );
    event Revoked(address indexed voucher, address indexed agent, uint64 at);

    error NotAnAgent(address account);
    error SelfVouch();
    error AlreadyVouched();
    error NotVouched();
    error NoteTooLong(uint256 length);

    /// @notice Vouch for an Agent ID holder, with a short public note.
    /// @param agent The Agent ID holder being vouched for. Must hold an Agent ID.
    /// @param note  Free-form note (max 160 bytes), stored on-chain.
    function vouch(address agent, string calldata note) external {
        _requireAgent(msg.sender);
        _requireAgent(agent);
        if (agent == msg.sender) revert SelfVouch();
        if (_voucherIndex[agent][msg.sender] != 0) revert AlreadyVouched();
        uint256 len = bytes(note).length;
        if (len > MAX_NOTE_BYTES) revert NoteTooLong(len);

        uint64 nowTs = uint64(block.timestamp);
        _vouch[msg.sender][agent] = Vouch({at: nowTs, note: note});
        _vouchers[agent].push(msg.sender);
        _voucherIndex[agent][msg.sender] = _vouchers[agent].length;
        vouchCount[agent] += 1;
        vouchesGiven[msg.sender] += 1;
        totalVouches += 1;

        emit Vouched(msg.sender, agent, note, nowTs);
    }

    /// @notice Withdraw a vouch you previously cast.
    function revoke(address agent) external {
        uint256 idx = _voucherIndex[agent][msg.sender];
        if (idx == 0) revert NotVouched();

        uint256 last = _vouchers[agent].length;
        if (idx != last) {
            address swapped = _vouchers[agent][last - 1];
            _vouchers[agent][idx - 1] = swapped;
            _voucherIndex[agent][swapped] = idx;
        }
        _vouchers[agent].pop();
        delete _voucherIndex[agent][msg.sender];
        delete _vouch[msg.sender][agent];
        vouchCount[agent] -= 1;
        vouchesGiven[msg.sender] -= 1;
        totalVouches -= 1;

        emit Revoked(msg.sender, agent, uint64(block.timestamp));
    }

    /// @notice Read a single vouch.
    /// @return exists Whether `voucher` currently vouches for `agent`.
    /// @return at     Timestamp the vouch was cast.
    /// @return note   The note attached to the vouch.
    function vouchOf(
        address voucher,
        address agent
    ) external view returns (bool exists, uint64 at, string memory note) {
        Vouch storage v = _vouch[voucher][agent];
        return (v.at != 0, v.at, v.note);
    }

    /// @notice Every address currently vouching for `agent`.
    function vouchersOf(
        address agent
    ) external view returns (address[] memory) {
        return _vouchers[agent];
    }

    /// @notice Page through the vouchers of `agent`.
    function vouchersOfPaged(
        address agent,
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory page, uint256 nextOffset) {
        address[] storage all = _vouchers[agent];
        if (offset >= all.length) return (new address[](0), all.length);
        uint256 end = offset + limit;
        if (end > all.length) end = all.length;
        page = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = all[i];
        }
        nextOffset = end;
    }

    /// @notice True when `account` holds at least one Agent ID.
    function isAgent(address account) public view returns (bool) {
        try IAgentID(AGENT_ID).balanceOf(account) returns (uint256 n) {
            return n > 0;
        } catch {
            return false;
        }
    }

    /// @notice Handle (without the `.ai` suffix) of `account`, or "" if none.
    /// @dev Convenience for contracts; the frontend can call handleOf directly.
    function handleOfSafe(
        address account
    ) external view returns (string memory) {
        try IAgentID(AGENT_ID).handleOf(account) returns (string memory h) {
            return h;
        } catch {
            return "";
        }
    }

    function _requireAgent(address account) private view {
        if (!isAgent(account)) revert NotAnAgent(account);
    }
}
