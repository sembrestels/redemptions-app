pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/apps-token-manager/contracts/TokenManager.sol";
import "@aragon/apps-vault/contracts/Vault.sol";
import "@aragon/os/contracts/lib/math/SafeMath.sol";
import "@aragon/os/contracts/common/EtherTokenConstant.sol";
import "./lib/ArrayUtils.sol";

contract Redemptions is AragonApp {
    using SafeMath for uint256;
    using ArrayUtils for address[];

    bytes32 constant public REDEEM_ROLE = keccak256("REDEEM_ROLE");
    bytes32 constant public ADD_TOKEN_ROLE = keccak256("ADD_TOKEN_ROLE");
    bytes32 constant public REMOVE_TOKEN_ROLE = keccak256("REMOVE_TOKEN_ROLE");
    bytes32 constant private REDEEM_MESSAGE = keccak256("I WOULD LIKE TO REDEEM SOME TOKENS PLEASE");

    string private constant ERROR_VAULT_NOT_CONTRACT = "REDEMPTIONS_VAULT_NOT_CONTRACT";
    string private constant ERROR_TOKEN_MANAGER_NOT_CONTRACT = "REDEMPTIONS_TOKEN_MANAGER_NOT_CONTRACT";
    string private constant ERROR_TOKEN_NOT_CONTRACT = "REDEMPTIONS_TOKEN_NOT_CONTRACT";
    string private constant ERROR_CANNOT_ADD_TOKEN_MANAGER = "REDEMPTIONS_CANNOT_ADD_TOKEN_MANAGER";
    string private constant ERROR_TOKEN_ALREADY_ADDED = "REDEMPTIONS_TOKEN_ALREADY_ADDED";
    string private constant ERROR_NOT_VAULT_TOKEN = "REDEMPTIONS_NOT_VAULT_TOKEN";
    string private constant ERROR_CANNOT_REDEEM_ZERO = "REDEMPTIONS_CANNOT_REDEEM_ZERO";
    string private constant ERROR_INCORRECT_MESSAGE = "REDEMPTIONS_INCORRECT_MESSAGE";
    string private constant ERROR_INSUFFICIENT_BALANCE = "REDEMPTIONS_INSUFFICIENT_BALANCE";

    Vault public vault;
    TokenManager public tokenManager;

    mapping(address => bool) public tokenAdded;
    address[] public redemptionTokenList;

    event AddToken(address indexed token);
    event RemoveToken(address indexed token);
    event Redeem(address indexed redeemer, uint256 amount);

    /**
    * @notice Initialize Redemptions app contract
    * @param _vault Address of the vault
    * @param _tokenManager TokenManager address
    * @param _redemptionTokenList token addreses
    */
    function initialize(Vault _vault, TokenManager _tokenManager, address[] _redemptionTokenList) external onlyInit {
        initialized();

        require(isContract(_vault), ERROR_VAULT_NOT_CONTRACT);
        require(isContract(_tokenManager), ERROR_TOKEN_MANAGER_NOT_CONTRACT);

        vault = _vault;
        tokenManager = _tokenManager;
        redemptionTokenList = _redemptionTokenList;

        for (uint i = 0; i < _redemptionTokenList.length; i++) {
            tokenAdded[_redemptionTokenList[i]] = true;
        }
    }

    /**
    * @notice Add token `_token` to redemption list
    * @param _token token address
    */
    function addToken(address _token) external auth(ADD_TOKEN_ROLE) {
        require(_token != address(tokenManager), ERROR_CANNOT_ADD_TOKEN_MANAGER);
        require(!tokenAdded[_token], ERROR_TOKEN_ALREADY_ADDED);

        if (_token != ETH) {
            require(isContract(_token), ERROR_TOKEN_NOT_CONTRACT);
        }

        tokenAdded[_token] = true;
        redemptionTokenList.push(_token);

        emit AddToken(_token);
    }

    /**
    * @notice Remove token `_token` from redemption list
    * @param _token token address
    */
    function removeToken(address _token) external auth(REMOVE_TOKEN_ROLE) {
        require(tokenAdded[_token], ERROR_NOT_VAULT_TOKEN);

        tokenAdded[_token] = false;
        redemptionTokenList.deleteItem(_token);

        emit RemoveToken(_token);
    }

    /**
    * @dev As we cannot get origin sender address when using a forwarder such as token manager, the best solution
    * we came up to is to make the redeemer to sign a message client side and get the signer address using ecrecover
    * @notice Redeem `_amount` redeemable tokens
    * @param _amount amount of tokens
    * @param msgHash message that was signed
    */
    function redeem(uint256 _amount,bytes32 msgHash, uint8 v, bytes32 r, bytes32 s) external auth(REDEEM_ROLE) {
        require(_amount > 0, ERROR_CANNOT_REDEEM_ZERO);
        require(REDEEM_MESSAGE == msgHash, ERROR_INCORRECT_MESSAGE);
        
        //get address that signed message
        address redeemer = recoverAddr(msgHash, v, r, s);
        require(tokenManager.spendableBalanceOf(redeemer) >= _amount, ERROR_INSUFFICIENT_BALANCE);

        uint256 redemptionAmount;
        uint256 tokenBalance;
        uint256 totalSuuply = tokenManager.token().totalSupply();

        for (uint256 i = 0; i < redemptionTokenList.length; i++) {
            tokenBalance = vault.balance(redemptionTokenList[i]);

            redemptionAmount = _amount.mul(tokenBalance).div(totalSuuply);
            vault.transfer(redemptionTokenList[i], redeemer, redemptionAmount);
        }

        tokenManager.burn(redeemer, _amount);

        emit Redeem(redeemer, _amount);
    }

    /**
    * @notice Get tokens from redemption list
    * @return token addresses
    */
    function getTokens() public view returns (address[]) {
        return redemptionTokenList;
    }

    /** Functions to make frontend app lighter */

    /**
    * @notice Get redeemable token address
    * @return redeemable token address
    */
    function getRedeemableToken() public view returns (address) {
        return tokenManager.token();
    }
    
    /**
    * @notice Get spendable balance of address
    * @return spendable balance of holder
    */
    function spendableBalanceOf(address holder) public view returns (uint256) {
        return tokenManager.spendableBalanceOf(holder);
    }



    function recoverAddr(bytes32 msgHash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix,msgHash));
        return ecrecover(prefixedHash, v, r, s);
    }
}