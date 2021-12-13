// SPDX-License-Identifier: MIT
pragma solidity =0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";

abstract contract AccessProtected is Context, Ownable {
    mapping(address => bool) private _admins; // user address => admin? mapping
    mapping(address => bool) private _minters; // user address => minter? mapping
    bool public publicMinting;

    event UserAccessSet(address _user, string _access, bool _enabled);

    /**
     * @notice Set Admin Access
     *
     * @param admin - Address of Minter
     * @param enabled - Enable/Disable Admin Access
     */
    function setAdmin(address admin, bool enabled) external onlyOwner {
        require(admin != address(0), "Invalid Admin Address");
        _admins[admin] = enabled;
        emit UserAccessSet(admin, "ADMIN", enabled);
    }

    /**
     * @notice Set Minter Access
     *
     * @param minter - Address of Minter
     * @param enabled - Enable/Disable Admin Access
     */
    function setMinter(address minter, bool enabled) public onlyAdmin {
        require(minter != address(0), "Invalid Minter Address");
        _minters[minter] = enabled;
        emit UserAccessSet(minter, "MINTER", enabled);
    }

    /**
     * @notice Set Minter Access
     *
     * @param minters - Address of Minters
     * @param enabled - Enable/Disable Admin Access
     */
    function setMinters(address[] calldata minters, bool enabled) external onlyAdmin {
        for (uint256 i = 0; i < minters.length; i++) {
            address minter = minters[i];
            setMinter(minter, enabled);
        }
    }

    /**
     * @notice Enable/Disable public Minting
     *
     * @param enabled - Enable/Disable
     */
    function setPublicMinting(bool enabled) external onlyAdmin {
        publicMinting = enabled;
        emit UserAccessSet(address(0), "MINTER", enabled);
    }

    /**
     * @notice Check Admin Access
     *
     * @param admin - Address of Admin
     * @return whether minter has access
     */
    function isAdmin(address admin) public view returns (bool) {
        return _admins[admin];
    }

    /**
     * @notice Check Minter Access
     *
     * @param minter - Address of minter
     * @return whether minter has access
     */
    function isMinter(address minter) public view returns (bool) {
        return _minters[minter];
    }

    /**
     * Throws if called by any account other than the Admin/Owner.
     */
    modifier onlyAdmin() {
        require(_admins[_msgSender()] || _msgSender() == owner(), "AccessProtected: caller is not admin");
        _;
    }

    /**
     * Throws if called by any account other than the Minter/Admin/Owner.
     */
    modifier onlyMinter() {
        require(
            publicMinting || _minters[_msgSender()] || _admins[_msgSender()] || _msgSender() == owner(),
            "AccessProtected: caller is not minter"
        );
        _;
    }
}
