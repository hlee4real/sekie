const {AptosClient, AptosAccount, CoinClient, TokenClient} = require('aptos');
const NODE_URL = "https://fullnode.devnet.aptoslabs.com"
const client = new AptosClient(NODE_URL);
const coinClient = new CoinClient(client);
const tokenClient = new TokenClient(client);
//lender is wallet1
let myWallet1 = AptosAccount.fromAptosAccountObject({
    address: "",
    publicKeyHex: "",
    privateKeyHex: "",
})
//borrower/nft owner is wallet2
let myWallet2 = AptosAccount.fromAptosAccountObject({
    address: "",
    publicKeyHex: "",
    privateKeyHex: "",
})
//module manager/contract deployer is wallet3
let myWallet3 = AptosAccount.fromAptosAccountObject({
    address: "",
    publicKeyHex: "",
    privateKeyHex: "",
})

const vinhDonLuaCollection = {
    name: "Vinh Don Lua",
    description: "Thich don lua vl",
    uri: "https://gamefi.org/api/v1/boxes/9"
}

const vinhDonLuaToken = {
    name: "Vinh Don Lua Token",
    description: "Thich don lua vl",
    uri: "https://gamefi.org/api/v1/boxes/10",
    supply: 1,
}

const main = async () => {
    console.log(`My wallet has ${await coinClient.checkBalance(myWallet1)} APT coins`)
    // await create_collection()
    // await create_token()
    // await init_pool()
    // await lender_offer()
    // await lender_revoke()
    // await borrow_select()
    await borrower_pay_loan()
}

const create_collection = async () => {
    try {
        const tx = await tokenClient.createCollection(
            myWallet2,
            vinhDonLuaCollection.name,
            vinhDonLuaCollection.description,
            vinhDonLuaCollection.uri,
        )
        await client.waitForTransaction(tx, {checkSuccess: true})
    } catch (error) {
        console.log("error create collection", error);
    }
}

const create_token = async () => {
    try {
        const tx = await tokenClient.createToken(
            myWallet2,
            vinhDonLuaCollection.name,
            vinhDonLuaToken.name,
            vinhDonLuaToken.description,
            vinhDonLuaToken.supply,
            vinhDonLuaToken.uri,
        )
        await client.waitForTransaction(tx, {checkSuccess: true})
    } catch (error) {
        console.log("error create token", error);
    }
}

const init_pool = async () => {
    try {
        const data = [
            myWallet2.address(),
            vinhDonLuaCollection.name,
            180,
            7,
        ]
        const tx = {
            type: 'entry_function_payload',
            function: '0x27b8415702fc14fc7f1345b519bf1bbe0b6f718793ca1d69fa0e59c307ce8eae::sekie::init_collection_pool',
            type_arguments: [],
            arguments: data,
        }
        await signAndSubmitWallet3(tx)
    } catch (error) {
        console.log("error init pool", error);
    }
}

const lender_offer = async () => {
    try {
        const data = [
            vinhDonLuaCollection.name,
            80000000
        ]
        const tx = {
            type: 'entry_function_payload',
            function: '0x27b8415702fc14fc7f1345b519bf1bbe0b6f718793ca1d69fa0e59c307ce8eae::sekie::lender_offer',
            type_arguments: ['0x1::aptos_coin::AptosCoin'],
            arguments: data,
        }
        await signAndSubmitWallet1(tx)
    }catch (error) {
        console.log("error lender offer", error);
    }
}
const lender_revoke = async () => {
    try{
        const tx = {
            type: 'entry_function_payload',
            function:  '0x27b8415702fc14fc7f1345b519bf1bbe0b6f718793ca1d69fa0e59c307ce8eae::sekie::lender_revoke',
            type_arguments: ['0x1::aptos_coin::AptosCoin'],
            arguments: [vinhDonLuaCollection.name],
        }
        await signAndSubmitWallet1(tx)
    }catch (error) {
        console.log("error lender revoke", error);
    }
}
const borrow_select = async () => {
    try{
        const data = [
            vinhDonLuaCollection.name,
            vinhDonLuaToken.name,
            0,
            myWallet1.address(),
        ]
        const tx = {
            type: 'entry_function_payload',
            function: '0x27b8415702fc14fc7f1345b519bf1bbe0b6f718793ca1d69fa0e59c307ce8eae::sekie::borrow_select',
            type_arguments: ['0x1::aptos_coin::AptosCoin'],
            arguments: data,
        }
        await signAndSubmitWallet2(tx)
    }catch (error) {
        console.log("error borrow select", error);
    }
}

const borrower_pay_loan = async () => {
    try{
        const tx = {
            type: 'entry_function_payload',
            function: '0x27b8415702fc14fc7f1345b519bf1bbe0b6f718793ca1d69fa0e59c307ce8eae::sekie::borrower_pay_loan',
            type_arguments: ['0x1::aptos_coin::AptosCoin'],
            arguments: [],
        }
        await signAndSubmitWallet2(tx)
    }catch (error) {
        console.log("error borrower pay loan", error);
    }
}



const signAndSubmitWallet2 = async (transaction) => {
    try {
        const txRequest = await client.generateTransaction(myWallet2.address(), transaction);
        const signedTx = await client.signTransaction(myWallet2, txRequest);
        const txResponse = await client.submitTransaction(signedTx);
        const result = await client.waitForTransaction(txResponse.hash);
        console.log("hash: ", txResponse.hash);
    }
    catch (e) {
        console.log('error sign and submit', e);
    }
}

const signAndSubmitWallet1 = async (transaction) => {
    try {
        const txRequest = await client.generateTransaction(myWallet1.address(), transaction);
        const signedTx = await client.signTransaction(myWallet1, txRequest);
        const txResponse = await client.submitTransaction(signedTx);
        const result = await client.waitForTransaction(txResponse.hash);
        console.log("hash: ", txResponse.hash);
    }
    catch (e) {
        console.log('error sign and submit', e);
    }
}

const signAndSubmitWallet3 = async (transaction) => {
    try {
        const txRequest = await client.generateTransaction(myWallet3.address(), transaction);
        const signedTx = await client.signTransaction(myWallet3, txRequest);
        const txResponse = await client.submitTransaction(signedTx);
        const result = await client.waitForTransaction(txResponse.hash);
        console.log("hash: ", txResponse.hash);
    }
    catch (e) {
        console.log('error sign and submit', e);
    }
}
main()