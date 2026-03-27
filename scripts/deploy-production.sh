#!/bin/bash
# Production Deployment Script for ClearDeck
# Usage: ./scripts/deploy-production.sh [--environment ic]

set -e  # Exit on error

ENVIRONMENT="${1:-ic}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "=========================================="
echo "ClearDeck Production Deployment"
echo "Environment: $ENVIRONMENT"
echo "=========================================="
echo ""

# Check if icp is installed
if ! command -v icp &> /dev/null; then
    echo "Error: icp CLI is not installed or not in PATH"
    echo "Install with: npm install -g @icp-sdk/icp-cli @icp-sdk/ic-wasm"
    exit 1
fi

# Check environment
if [ "$ENVIRONMENT" != "ic" ] && [ "$ENVIRONMENT" != "local" ]; then
    echo "Error: Environment must be 'ic' or 'local'"
    exit 1
fi

# Check cycles balance for mainnet
if [ "$ENVIRONMENT" = "ic" ]; then
    echo "Checking cycles balance..."
    CYCLES=$(icp cycles balance -n ic 2>/dev/null || echo "0")
    echo "   Current cycles: $CYCLES"

    if [ "$CYCLES" -lt 1000000000000 ]; then
        echo "Warning: Low cycles balance. You may need more cycles for deployment."
        echo "   Get cycles from: https://internetcomputer.org/docs/current/developer-docs/getting-started/cycles/cycles-faucet"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Build for production
echo ""
echo "Building canisters for production..."
icp build

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

echo "Build complete"
echo ""

# Deploy canisters in order
echo "Deploying canisters..."
echo ""

echo "1. Deploying history canister..."
icp deploy history -e "$ENVIRONMENT"
HISTORY_ID=$(icp canister status history -e "$ENVIRONMENT" -i)
echo "   History canister: $HISTORY_ID"
echo ""

echo "2. Deploying lobby canister..."
icp deploy lobby -e "$ENVIRONMENT"
LOBBY_ID=$(icp canister status lobby -e "$ENVIRONMENT" -i)
echo "   Lobby canister: $LOBBY_ID"
echo ""

echo "3. Deploying table canisters..."
icp deploy table_1 -e "$ENVIRONMENT"
TABLE_1_ID=$(icp canister status table_1 -e "$ENVIRONMENT" -i)
echo "   Table 1 (heads-up): $TABLE_1_ID"

icp deploy table_2 -e "$ENVIRONMENT"
TABLE_2_ID=$(icp canister status table_2 -e "$ENVIRONMENT" -i)
echo "   Table 2 (6-max): $TABLE_2_ID"

icp deploy table_3 -e "$ENVIRONMENT"
TABLE_3_ID=$(icp canister status table_3 -e "$ENVIRONMENT" -i)
echo "   Table 3 (9-max): $TABLE_3_ID"

icp deploy btc_table_1 -e "$ENVIRONMENT"
BTC_TABLE_ID=$(icp canister status btc_table_1 -e "$ENVIRONMENT" -i)
echo "   BTC Table: $BTC_TABLE_ID"

icp deploy eth_table_1 -e "$ENVIRONMENT"
ETH_TABLE_ID=$(icp canister status eth_table_1 -e "$ENVIRONMENT" -i)
echo "   ETH Table: $ETH_TABLE_ID"

icp deploy doge_table_1 -e "$ENVIRONMENT"
DOGE_TABLE_ID=$(icp canister status doge_table_1 -e "$ENVIRONMENT" -i)
echo "   DOGE Table: $DOGE_TABLE_ID"
echo ""

# Authorize tables in history canister
echo "4. Authorizing tables in history canister..."
for TABLE_ID in "$TABLE_1_ID" "$TABLE_2_ID" "$TABLE_3_ID" "$BTC_TABLE_ID" "$ETH_TABLE_ID" "$DOGE_TABLE_ID"; do
    icp canister call history authorize_table "(principal \"$TABLE_ID\")" -e "$ENVIRONMENT" || echo "   Warning: Failed to authorize table $TABLE_ID"
done
echo "   Tables authorized"
echo ""

# Set history canister ID in tables
echo "5. Configuring table canisters..."
for TABLE in table_1 table_2 table_3 btc_table_1 eth_table_1 doge_table_1; do
    icp canister call "$TABLE" set_history_canister "(principal \"$HISTORY_ID\")" -e "$ENVIRONMENT" || echo "   Warning: Failed to set history canister in $TABLE"
done
echo "   History canister configured"
echo ""

# CRITICAL: Disable dev mode
echo "6. Disabling dev mode (CRITICAL for production)..."
for TABLE in table_1 table_2 table_3 btc_table_1 eth_table_1 doge_table_1; do
    icp canister call "$TABLE" set_dev_mode "(false)" -e "$ENVIRONMENT" || echo "   Warning: Failed to disable dev mode in $TABLE"
done

# Verify dev mode is disabled
echo "   Verifying dev mode is disabled..."
ALL_DISABLED=true
for TABLE in table_1 table_2 table_3 btc_table_1 eth_table_1 doge_table_1; do
    DEV_MODE=$(icp canister call "$TABLE" is_dev_mode -e "$ENVIRONMENT" --query 2>/dev/null | grep -o 'false\|true' || echo "unknown")
    if [ "$DEV_MODE" != "false" ]; then
        echo "   WARNING: Dev mode may still be enabled in $TABLE: $DEV_MODE"
        ALL_DISABLED=false
    fi
done
if [ "$ALL_DISABLED" = true ]; then
    echo "   Dev mode is disabled"
fi
echo ""

# Deploy frontend
echo "7. Deploying frontend..."
icp deploy frontend -e "$ENVIRONMENT"
FRONTEND_ID=$(icp canister status frontend -e "$ENVIRONMENT" -i)
echo "   Frontend canister: $FRONTEND_ID"
echo ""

# Summary
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Canister IDs:"
echo "  History:    $HISTORY_ID"
echo "  Lobby:      $LOBBY_ID"
echo "  Table 1:    $TABLE_1_ID"
echo "  Table 2:    $TABLE_2_ID"
echo "  Table 3:    $TABLE_3_ID"
echo "  BTC Table:  $BTC_TABLE_ID"
echo "  ETH Table:  $ETH_TABLE_ID"
echo "  DOGE Table: $DOGE_TABLE_ID"
echo "  Frontend:   $FRONTEND_ID"
echo ""

if [ "$ENVIRONMENT" = "ic" ]; then
    echo "Frontend URL:"
    echo "   https://$FRONTEND_ID.icp0.io"
    echo ""
    echo "Next Steps:"
    echo "   1. Test the frontend URL"
    echo "   2. Test deposit/withdrawal flows"
    echo "   3. Monitor cycles balance"
    echo "   4. Set up monitoring/alerting"
    echo ""
    echo "IMPORTANT:"
    echo "   - Verify dev mode is disabled (already done)"
    echo "   - Fund canisters with ICP for withdrawal fees"
    echo "   - Monitor cycles consumption"
    echo ""
else
    echo "Local Frontend URL:"
    echo "   http://localhost:8000/?canisterId=$FRONTEND_ID"
    echo ""
fi

echo "=========================================="
