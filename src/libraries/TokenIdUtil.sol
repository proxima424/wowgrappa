// SPDX-License-Identifier: MIT
// solhint-disable max-line-length

pragma solidity ^0.8.0;

import "../config/enums.sol";
import "../config/errors.sol";

/**
 * Token ID =
 *
 *  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
 *  | tokenType (24 bits) | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | shortStrike (64 bits) |
 *  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
 */

/**
 * Compressed Token ID =
 *
 *  * ------------------- | ------------------- | ---------------- | -------------------- *
 *  | tokenType (24 bits) | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) |
 *  * ------------------- | ------------------- | ---------------- | -------------------- *
 */
library TokenIdUtil {
    function getTokenId(TokenType tokenType, uint40 productId, uint256 expiry, uint256 longStrike, uint256 shortStrike)
        internal
        pure
        returns (uint256 tokenId)
    {
        tokenId = formatTokenId(tokenType, productId, uint64(expiry), uint64(longStrike), uint64(shortStrike));
    }

    /**
     * @notice calculate ERC1155 token id for given option parameters. See table above for tokenId
     * @param tokenType TokenType enum
     * @param productId if of the product
     * @param expiry timestamp of option expiry
     * @param longStrike strike price of the long option, with 6 decimals
     * @param shortStrike strike price of the short (upper bond for call and lower bond for put) if this is a spread. 6 decimals
     * @return tokenId token id
     */
    function formatTokenId(TokenType tokenType, uint40 productId, uint64 expiry, uint64 longStrike, uint64 shortStrike)
        internal
        pure
        returns (uint256 tokenId)
    {
        unchecked {
            tokenId = (uint256(tokenType) << 232) + (uint256(productId) << 192) + (uint256(expiry) << 128)
                + (uint256(longStrike) << 64) + uint256(shortStrike);
        }
    }

    /**
     * @notice calculate non-complaint ERC1155 token id for given option parameters. See table above for shorttokenId
     * @param tokenType TokenType enum
     * @param productId if of the product
     * @param expiry timestamp of option expiry
     * @param longStrike strike price of the long option, with 6 decimals
     * @return tokenId token id
     */
    function formatShortTokenId(TokenType tokenType, uint40 productId, uint64 expiry, uint64 longStrike)
        internal
        pure
        returns (uint192 tokenId)
    {
        unchecked {
            tokenId = (uint192(tokenType) << 168) + (uint192(productId) << 128) + (uint192(expiry) << 64) + uint192(longStrike);
        }
    }

    /**
     * @notice derive option, product, expiry and strike price from ERC1155 token id
     * @dev    See table above for tokenId composition
     * @param tokenId token id
     * @return tokenType TokenType enum
     * @return productId 32 bits product id
     * @return expiry timestamp of option expiry
     * @return longStrike strike price of the long option, with 6 decimals
     * @return shortStrike strike price of the short (upper bond for call and lower bond for put) if this is a spread. 6 decimals
     */
    function parseTokenId(uint256 tokenId)
        internal
        pure
        returns (TokenType tokenType, uint40 productId, uint64 expiry, uint64 longStrike, uint64 shortStrike)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tokenType := shr(232, tokenId)
            productId := shr(192, tokenId)
            expiry := shr(128, tokenId)
            longStrike := shr(64, tokenId)
            shortStrike := tokenId
        }
    }

    /**
     * @notice parse collateral id from tokenId
     * @dev more efficient than parsing tokenId and than parse productId
     * @param tokenId token id
     * @return collatearlId
     */
    function parseCollateralId(uint256 tokenId) internal pure returns (uint8 collatearlId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // collateralId is the last bits of productId
            collatearlId := shr(192, tokenId)
        }
    }

    /**
     * @notice parse engine id from tokenId
     * @dev more efficient than parsing tokenId and than parse productId
     * @param tokenId token id
     * @return engineId
     */
    function parseEnginelId(uint256 tokenId) internal pure returns (uint8 engineId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // collateralId is the last bits of productId
            engineId := shr(216, tokenId) // 192 to get product id, another 24 to get engineId
        }
    }

    /**
     * @notice derive option, product, expiry and strike price from short token id (no shortStrike)
     * @dev    See table above for tokenId composition
     * @param tokenId token id
     * @return tokenType TokenType enum
     * @return productId 32 bits product id
     * @return expiry timestamp of option expiry
     * @return longStrike strike price of the long option, with 6 decimals
     */
    function parseShortTokenId(uint192 tokenId)
        internal
        pure
        returns (TokenType tokenType, uint40 productId, uint64 expiry, uint64 longStrike)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tokenType := shr(168, tokenId)
            productId := shr(128, tokenId)
            expiry := shr(64, tokenId)
            longStrike := tokenId
        }
    }

    /**
     * @notice derive option type from ERC1155 token id
     * @param tokenId token id
     * @return tokenType TokenType enum
     */
    function parseTokenType(uint256 tokenId) internal pure returns (TokenType tokenType) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tokenType := shr(232, tokenId)
        }
    }

    /**
     * @notice derive if option is expired from ERC1155 token id
     * @param tokenId token id
     * @return expired bool
     */
    function isExpired(uint256 tokenId) internal view returns (bool expired) {
        uint64 expiry;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            expiry := shr(128, tokenId)
        }

        expired = block.timestamp >= expiry;
    }

    /**
     * @notice convert an spread tokenId back to put or call.
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     * @dev   oldId =   | spread type (24 b)  | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | shortStrike (64 bits) |
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     * @dev   newId =   | call or put type    | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | 0           (64 bits) |
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     * @dev   this function will: override tokenType, remove shortStrike.
     * @param _tokenId token id to change
     */
    function convertToVanillaId(uint256 _tokenId) internal pure returns (uint256 newId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            newId := shr(64, _tokenId) // step 1: >> 64 to wipe out shortStrike
            newId := shl(64, newId) // step 2: << 64 go back

            newId := sub(newId, shl(232, 1)) // step 3: new tokenType = spread type - 1
        }
    }

    /**
     * @notice convert an spread tokenId back to put or call.
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     * @dev   oldId =   | call or put type    | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | 0           (64 bits) |
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     * @dev   newId =   | spread type         | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | shortStrike (64 bits) |
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     *
     * this function convert put or call type to spread type, add shortStrike.
     * @param _tokenId token id to change
     * @param _shortStrike strike to add
     */
    function convertToSpreadId(uint256 _tokenId, uint256 _shortStrike) internal pure returns (uint256 newId) {
        // solhint-disable-next-line no-inline-assembly
        unchecked {
            newId = _tokenId + _shortStrike;
            return newId + (1 << 232); // new type (spread type) = old type + 1
        }
    }

    /**
     * @notice Compresses tokenId by removing shortStrike.
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     * @dev   oldId =   | call or put type    | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | 0           (64 bits) |
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     *                  * ------------------- | ------------------- | ---------------- | -------------------- *
     * @dev   newId =   | call or put type    | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) |
     *                  * ------------------- | ------------------- | ---------------- | -------------------- *
     *
     * @param _tokenId token id to change
     */
    function compress(uint256 _tokenId) internal pure returns (uint192 newId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            newId := shr(64, _tokenId) // >> 64 to wipe out shortStrike
        }
    }

    /**
     * @notice convert a shortened tokenId back ERC1155 compliant.
     *                  * ------------------- | ------------------- | ---------------- | -------------------- *
     * @dev   oldId =   | call or put type    | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) |
     *                  * ------------------- | ------------------- | ---------------- | -------------------- *
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     * @dev   newId =   | call or put type    | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | 0           (64 bits) |
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     *
     * @param _tokenId token id to change
     */
    function expand(uint192 _tokenId) internal pure returns (uint256 newId) {
        newId = uint256(_tokenId);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            newId := shl(64, newId)
        }
    }
}
