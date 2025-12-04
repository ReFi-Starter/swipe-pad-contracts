import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
    solidity: "0.8.20",
    networks: {
        hardhat: {
        },
        sepolia: {
            url: "https://sepolia-forno.celo-testnet.org",
            // CORRECTED: Must use process.env.PRIVATE_KEY
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [], 
            chainId: 11142220,
            timeout: 120000,
        },
        celo: {
            url: "https://forno.celo.org",
            // CORRECTED: Must use process.env.PRIVATE_KEY
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
            chainId: 42220,
        },
    },
};

export default config;
