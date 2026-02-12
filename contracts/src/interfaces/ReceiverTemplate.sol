// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IReceiver} from "./IReceiver.sol";

/// @title ReceiverTemplate - simplified CRE receiver with forwarder check
abstract contract ReceiverTemplate is IReceiver {
    address public immutable FORWARDER;

    error UnauthorizedForwarder(address sender);

    constructor(address forwarder) {
        FORWARDER = forwarder;
    }

    function onReport(bytes calldata metadata, bytes calldata report) external override {
        if (msg.sender != FORWARDER) {
            revert UnauthorizedForwarder(msg.sender);
        }
        _processReport(report);
    }

    function _processReport(bytes calldata report) internal virtual;

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || interfaceId == 0x01ffc9a7;
    }
}
