// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {IERC721} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Receiver} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721Errors} from "../../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {IERC165} from "../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

contract ERC721 is IERC721Metadata {
    string public override name;

    string public override symbol;

    mapping(uint256 => address) private _owners;

    mapping(uint256 => string) private _uriMapping;

    mapping(address => uint256) private _balances;

    mapping(uint256 => address) private _tokenApprovals;

    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint256 private idCounter;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view override returns (uint256 balance) {
        return _balances[owner];
    }

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) public view override returns (address owner) {
        owner = _owners[tokenId];
        require(owner != address(0), "token doesn't exist");
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
        address owner = ownerOf(tokenId);
        require(_isApprovedOrOwner(owner, msg.sender, tokenId), "not owner nor approved");
        _safeTransfer(owner, from, to, tokenId, data);
    }

    function _safeTransfer(address owner, address from, address to, uint256 tokenId, bytes memory data) private {
        _transfer(owner, from, to, tokenId);
        _checkOnERC721Received(from, to, tokenId, data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or
     *   {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        safeTransferFrom(from, to, tokenId, bytes(""));
    }

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC721
     * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external override {
        address owner = ownerOf(tokenId);
        require(_isApprovedOrOwner(owner, msg.sender, tokenId), "not owner nor approved");
        _transfer(owner, from, to, tokenId);
    }

    function _isApprovedOrOwner(address owner, address from, uint256 tokenId) private view returns (bool) {
        return owner == from || isApprovedForAll(owner, from) || getApproved(tokenId) == from;
    }

    function _transfer(address owner, address from, address to, uint256 tokenId) private {
        require(from == owner, "not owner");
        require(to != address(0), "do not transfer to address 0");
        // NFT 转账前要取消之前的授权
        _approve(owner, address(0), tokenId);
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external override {
        address owner = ownerOf(tokenId);
        require(owner == msg.sender || _operatorApprovals[owner][msg.sender], "not owner nor approved for all");
        _approve(owner, to, tokenId);
    }

    function _approve(address owner, address to, uint256 tokenId) private {
        require(owner != to, "do not approve for self");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the address zero.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved) external override {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) public view override returns (address operator) {
        require(_owners[tokenId] != address(0), "token does not exists");
        return _tokenApprovals[tokenId];
    }

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC721).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function mintNft(address owner, string memory tokenURIStr) external returns (uint256) {
        idCounter++;
        assert(_owners[idCounter] == address(0));
        _mint(owner, idCounter);
        _uriMapping[idCounter] = tokenURIStr;
        _checkOnERC721Received(address(0), owner, idCounter, "");
        return idCounter;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_owners[tokenId] != address(0), "uri not exists");
        return _uriMapping[tokenId];
    }

    function _mint(address owner, uint256 tokenId) private {
        _owners[tokenId] = owner;
        _balances[owner]++;
        emit Transfer(address(0), owner, tokenId);
    }

    function _checkOnERC721Received(address operator, address to, uint256 tokenId, bytes memory data) private {
        // 如果接收地址是一个合约的话，必须实现IERC721Receiver接口，否则一旦NTF接收后，有可能永远也无法被转出
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, operator, tokenId, data) returns (bytes4 retval) {
                if (retval != IERC721Receiver.onERC721Received.selector) {
                    revert IERC721Errors.ERC721InvalidReceiver(to);
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert IERC721Errors.ERC721InvalidReceiver(to);
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }
}
