import './App.css'
import { useState, useEffect, useRef } from 'react'
import { formatBalance, formatChainInDecimalAsString } from './utils'
import { ethers } from "ethers";
import NFTMarketABI from "./utils/NFTMarketABI.json"
import ERC777TokenGTTABI from "./utils/ERC777TokenGTTABI.json"
import ERC721TokenABI from "./utils/ERC721Token.json"
import BigNumber from 'bignumber.js';

interface WalletState { accounts: string[], signer: ethers.JsonRpcSigner | null, chainId: string, balance: number | string }
interface NFTInfo {
  tokenId: number;
  priceInUSD: string;
}
interface NFTListStatus {
  [NFTAddress: string]: NFTInfo[];
}
let GTTAddress: string = ""
let NFTMarketAddress: string = ""
let GTTContract: ethers.Contract
let NFTMarket: ethers.Contract
let ERC721TokenContract: ethers.Contract
let scanURL: string = ''
let TxURL_List: string | null = null
let TxURL_Delist: string | null = null
let TxURL_Buy: string | null = null
// let ListedNFT: NFTListStatus = {}
const initialState = { accounts: [], signer: null, balance: "", chainId: "" }
const App = () => {
  const [ListedNFT, setListedNFT] = useState<NFTListStatus>({});
  const [wallet, setWallet] = useState<WalletState>(initialState)
  const [isConnecting, setIsConnecting] = useState(false)
  const [isNFTMarketApproved, setisNFTMarketApproved] = useState(true)
  const [error, setError] = useState(false)
  const [errorMessage, setErrorMessage] = useState("")
  const [GTTBalance, setGTTBalance] = useState<number | string>("");
  const NFTAddressRef_List = useRef<HTMLInputElement>(null);
  const tokenIdRef_List = useRef<HTMLInputElement>(null);
  const NFTPriceRef_List = useRef<HTMLInputElement>(null);
  const NFTAddressRef_Delist = useRef<HTMLInputElement>(null);
  const tokenIdRef_Delist = useRef<HTMLInputElement>(null);
  const NFTAddressRef_Buy = useRef<HTMLInputElement>(null);
  const tokenIdRef_Buy = useRef<HTMLInputElement>(null);
  const bidValueRef_Buy = useRef<HTMLInputElement>(null);
  const disableConnect = Boolean(wallet) && isConnecting

  // ERC20-Permit inputs
  const permit_Name = useRef<HTMLInputElement>(null);
  const permit_ChainId = useRef<HTMLInputElement>(null);
  const permit_VerifyingContract = useRef<HTMLInputElement>(null);
  const permit_Spender = useRef<HTMLInputElement>(null);
  const permit_ApprovedValue = useRef<HTMLInputElement>(null);
  const permit_Deadline = useRef<HTMLInputElement>(null);
  const permit_SignerAddr = useRef<HTMLInputElement>(null);

  // NFT-Permit inputs
  const permit_Name_NFT = useRef<HTMLInputElement>(null);
  const permit_ChainId_NFT = useRef<HTMLInputElement>(null);
  const permit_VerifyingContract_NFT = useRef<HTMLInputElement>(null);
  const permit_NFTSeller_NFT = useRef<HTMLInputElement>(null);
  const permit_buyer_NFT = useRef<HTMLInputElement>(null);
  const permit_tokenId_NFT = useRef<HTMLInputElement>(null);
  const permit_deadline_NFT = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let provider: ethers.BrowserProvider
    const refreshAccounts = async () => {
      const accounts = await _updateAccounts()
      _updateState(accounts)
    }

    const refreshChain = async (rawChainId: any) => {
      const chainId = formatChainInDecimalAsString(rawChainId)
      const accounts = await _updateAccounts()
      const balance = await _updateBalance(accounts)
      setWallet((wallet) => ({ ...wallet, balance, chainId }))
      _updateInfoOfChain(chainId)
      _updateContract()
      await _updateTokenBalance(accounts)
    }

    const initialization = async () => {
      provider = new ethers.BrowserProvider(window.ethereum)
      if (provider) {
        if (wallet.accounts.length > 0) {
          refreshAccounts()
        } else {
          setWallet(initialState)
        }

        window.ethereum.on('accountsChanged', refreshAccounts)
        window.ethereum.on("chainChanged", refreshChain)
      }
    }

    initialization()

    return () => {
      window.ethereum?.removeListener('accountsChanged', refreshAccounts)
      window.ethereum?.removeListener("chainChanged", refreshChain)
    }
  }, [])

  const handleNFTMarket_List = async () => {
    const NFTAddress = NFTAddressRef_List.current?.value;
    const tokenId = tokenIdRef_List.current?.value;
    const NFTPrice = NFTPriceRef_List.current?.value;
    const isApproved = await NFTMarket.checkIfApprovedByNFT(NFTAddress, tokenId);
    const ownerOfNFT = await NFTMarket.getNFTOwner(NFTAddress, tokenId);
    try {
      if (ownerOfNFT == NFTMarketAddress) {
        setError(true)
        setErrorMessage("This NFT has already listed in this NFTMarket")
        // if (NFTAddress && tokenId) {
        //   const tokenIdNum = parseInt(tokenId);
        //   setListedNFT(prevListedNFT => {
        //     const updatedList = { ...prevListedNFT };
        //     if (!updatedList[NFTAddress]) {
        //       updatedList[NFTAddress] = [];
        //     }
        //     updatedList[NFTAddress].push(tokenIdNum);
        //     return updatedList;
        //   });
        // }
        setError(false)
        return
      }
      if (!isApproved) {
        setError(true)
        setErrorMessage("Before listing NFT, this NFTMarket should be approved by corresponding NFT in advance")
        setisNFTMarketApproved(false)
        return
      }
      let tx = await NFTMarket.list(NFTAddress, tokenId, NFTPrice)
      TxURL_List = scanURL + 'tx/' + tx.hash
      const receipt = await tx.wait()
      _updateStateAfterTx(receipt)
      if (receipt) {
        if (NFTAddress && tokenId) {
          let priceBefore_Period1;
          let priceBefore_Period2;
          let isRecorded = false;
          const tokenIdNum = parseInt(tokenId);
          const priceInWETH = await NFTMarket.getNFTPrice_CountedInWETH(NFTAddress, tokenIdNum);
          console.log("priceInWETH_uintWei: ", priceInWETH);
          const [roundId_Latest, _, timeStamp_Latest] = await NFTMarket.getLatestPrice_ETH_USD();
          console.log("roundId_Latest", roundId_Latest);
          console.log("timeStamp_Latest", timeStamp_Latest);
          for (let i = roundId_Latest - BigInt(1); i > 0; i--) {
            console.log("loop starts!");
            const [priceOfRound, timeStamp] = await NFTMarket.getPriceOfRound(i);
            console.log("priceOfRound | in loop @i = ", i, priceOfRound);
            console.log("timeStamp | in loop @i = ", i, timeStamp);
            if (timeStamp <= timeStamp_Latest - BigInt(300) && isRecorded == false) {
              priceBefore_Period1 = priceOfRound;
              isRecorded = true;
              console.log("priceBefore_Period1: ", priceBefore_Period1);
            }
            if (timeStamp <= timeStamp_Latest - BigInt(600)) {
              priceBefore_Period2 = priceOfRound;
              console.log("priceBefore_Period2: ", priceBefore_Period2);
              break;
            }          
          }
          
          const ETHPriceInUSD = (priceBefore_Period1 + priceBefore_Period2) / BigInt(2);
          console.log("ETHPriceInUSD", ETHPriceInUSD);
          const priceInWETH_BigNumber = new BigNumber(priceInWETH.toString());
          const ETHPriceInUSD_BigNumber = new BigNumber(ETHPriceInUSD.toString());
          // The ETH/USD price derived from PriceFeed has a decimal of 8(i.e. 10 ** 8)
          const priceWithoutDecimals = priceInWETH_BigNumber.multipliedBy(ETHPriceInUSD_BigNumber).dividedBy(new BigNumber("10").pow(18 + 8));
          const price = priceWithoutDecimals.toFixed(3);
          console.log("price", price);
          const object = {tokenId: tokenIdNum, priceInUSD: price}
          setListedNFT(prevListedNFT => {
            const updatedList = { ...prevListedNFT };
            if (!updatedList[NFTAddress]) {
              updatedList[NFTAddress] = [];
            }
            updatedList[NFTAddress].push(object);
            return updatedList;
          });
        }
      }
      setError(false)
    } catch (err: any) {
      setError(true)
      setErrorMessage(err.message)
    }
  }

  const handleNFTMarket_Delist = async () => {
    const NFTAddress = NFTAddressRef_Delist.current?.value;
    const tokenId = tokenIdRef_Delist.current?.value;
    const ownerOfNFT = await NFTMarket.getNFTOwner(NFTAddress, tokenId);
    try {
      if (ownerOfNFT != NFTMarketAddress) {
        setError(true)
        setErrorMessage("This NFT is not listed in this NFTMarket")
        return
      }
      let tx = await NFTMarket.delist(NFTAddress, tokenId)
      const receipt = await tx.wait()
      _updateStateAfterTx(receipt)
      if (receipt) {
        if (NFTAddress && tokenId) {
          const tokenIdNum = parseInt(tokenId);
          
          if (ListedNFT[NFTAddress]) {
            const updatedTokenInfos = ListedNFT[NFTAddress].filter(nftInfo => nftInfo.tokenId !== tokenIdNum);
            if (updatedTokenInfos.length === 0) {
              const updatedListedNFT = { ...ListedNFT };
              delete updatedListedNFT[NFTAddress];
              setListedNFT(updatedListedNFT);
            } else {
              setListedNFT({ ...ListedNFT, [NFTAddress]: updatedTokenInfos });
            }
          }
        }
      }
      TxURL_Delist = scanURL + 'tx/' + tx.hash
      setError(false)
    } catch (err: any) {
      setError(true)
      setErrorMessage(err.message)
    }
  }

  const handleNFTMarket_Buy = async () => {
    const NFTAddress = NFTAddressRef_Buy.current?.value;
    const tokenId = tokenIdRef_Buy.current?.value;
    const bidValue = bidValueRef_Buy.current?.value;
    const ownerOfNFT = await NFTMarket.getNFTOwner(NFTAddress, tokenId);
    try {
      if (ownerOfNFT != NFTMarketAddress) {
        setError(true)
        setErrorMessage("This NFT has not listed in this NFTMarket")
        return
      }
      let tx = await NFTMarket.buy(NFTAddress, tokenId, bidValue)
      TxURL_Buy = scanURL + 'tx/' + tx.hash
      const receipt = await tx.wait()
      _updateStateAfterTx(receipt)
      setError(false)
    } catch (err: any) {
      setError(true)
      setErrorMessage(err.message)
    }
  }

  const handleNFT_Approve = async () => {
    let provider = new ethers.BrowserProvider(window.ethereum)
    let signer = await provider.getSigner()
    const NFTAddress = NFTAddressRef_List.current?.value;
    const tokenId = tokenIdRef_List.current?.value;
    if (NFTAddress) {
      ERC721TokenContract = new ethers.Contract(NFTAddress, ERC721TokenABI, signer)
    }
    const tx = await ERC721TokenContract.approve(NFTMarketAddress, tokenId)
    const receipt = await tx.wait()
    _updateStateAfterTx(receipt)
    if (receipt) {
      setisNFTMarketApproved(true)
    }
    setError(false)
  }

  const _updateStateAfterTx = (receipt: any) => {
    if (receipt) {
      _updateBalance(wallet.accounts)
      _updateTokenBalance(wallet.accounts)
    }
  }

  const _updateInfoOfChain = (chainId: string) => {
    switch (chainId) {
      // Mumbai
      case '80001':
        GTTAddress = "0xDBaA831fc0Ff91FF67A3eD5C6c708E6854CE6EfF"
        NFTMarketAddress = "0xF0B5972a88F201B1a83d87a1de2a6569d66fac58"
        scanURL = 'https://mumbai.polygonscan.com/'
        break;

      // Ethereum Goerli
      case '5':
        GTTAddress = "0x6307230425563aA7D0000213f579516159CDf84a"
        NFTMarketAddress = "0xAFD443aF73e81BFBA794124083b4C71aEbdC25BF"
        scanURL = 'https://goerli.etherscan.io/'
        break;

      // Ethereum Sepolia
      case '11155111':
        GTTAddress = "0x3490ff3bc24146AA6140e1efd5b0A0fAAEda39E9"
        // NFTMarketAddress = "0x73f81AA12c668506B3f3a96F8364d723c7647697" // The contract deployed by Remix
        NFTMarketAddress = "0xa81C1b905d3D9fe0c5BE1982F71d80a95f7BA028"
        scanURL = 'https://sepolia.etherscan.io/'
        break;

      default:
        GTTAddress = ""
        NFTMarketAddress = ""
    }
  }

  const _updateState = async (accounts: any) => {
    const chainId = await _updateChainId()
    const balance = await _updateBalance(accounts)
    let provider = new ethers.BrowserProvider(window.ethereum)
    let signer = await provider.getSigner()
    if (accounts.length > 0) {
      setWallet({ ...wallet, accounts, chainId, signer, balance })
    } else {
      setWallet(initialState)
    }
    _updateInfoOfChain(chainId)
    await _updateContract()
    await _updateTokenBalance(accounts)
  }

  const _updateContract = async () => {
    let provider = new ethers.BrowserProvider(window.ethereum)
    let signer = await provider.getSigner()
    NFTMarket = new ethers.Contract(NFTMarketAddress, NFTMarketABI, signer)
    GTTContract = new ethers.Contract(GTTAddress, ERC777TokenGTTABI, signer)
  }

  const _updateBalance = async (accounts: any) => {
    const balance = formatBalance(await window.ethereum!.request({
      method: "eth_getBalance",
      params: [accounts[0], "latest"],
    }))
    return balance
  }

  const _updateTokenBalance = async (accounts: any) => {
    setGTTBalance(formatBalance(await GTTContract.balanceOf(accounts[0])))
  }

  const _updateAccounts = async () => {
    const accounts = await window.ethereum.request(
      { method: 'eth_accounts' }
    )
    return accounts
  }

  const _updateChainId = async () => {
    const chainId = formatChainInDecimalAsString(await window.ethereum!.request({
      method: "eth_chainId",
    }))
    setWallet({ ...wallet, chainId })
    return chainId
  }

  const getLogs = async (fromBlock: number, toBlock: number) => {
    // const userAddress = wallet.accounts[0]
    let filter = {
      fromBlock, toBlock,
      address: NFTMarketAddress,
    }
    let provider = new ethers.BrowserProvider(window.ethereum)
    let currentBlock = await provider.getBlockNumber()
    if (filter.toBlock > currentBlock) {
      filter.toBlock = currentBlock;
    }
    provider.getLogs(filter).then(logs => {
      if (logs.length > 0) decodeEvents(logs)
      if (currentBlock <= fromBlock && logs.length == 0) {
        // console.log("begin monitor")
        // 方式1，继续轮训
        // setTimeout(() => {
        //     getLogs(fromBlock, toBlock)
        // }, 2000);
        // 方式2: 监听
        NFTMarket.on("NFTListed", function (a0, a1, a2, a3, event) {
          decodeEvents([event.log])
        })
        NFTMarket.on("NFTDelisted", function (a0, a1, event) {
          decodeEvents([event.log])
        })
        // NFTMarket.on("NFTBought", function (a0, a1, a2, event) {
        //   decodeEvents([event.log])
        // })
        NFTMarket.on("NFTBoughtWithGTST", function (a0, a1, a2, a3, event) {
          decodeEvents([event.log])
        })
      } else {
        getLogs(toBlock + 1, toBlock + 1 + 200)
      }
    })
  }

  function decodeEvents(logs: any) {
    const event_NFTListed = NFTMarket.getEvent("NFTListed").fragment
    const event_NFTDelisted = NFTMarket.getEvent("NFTDelisted").fragment
    const event_NFTBought = NFTMarket.getEvent("NFTBought").fragment

    for (var i = 0; i < logs.length; i++) {
      const item = logs[i]
      const eventId = item.topics[0]
      if (eventId == event_NFTListed.topicHash) {
        const data = NFTMarket.interface.decodeEventLog(event_NFTListed, item.data, item.topics)
        printLog(`NFTListed@Block#${item.blockNumber} | Parameters: { NFTAddress: ${data.NFTAddr}, tokenId: ${data.tokenId}, price: ${data.price} } (${item.transactionHash})`)
      } else if (eventId == event_NFTDelisted.topicHash) {
        const data = NFTMarket.interface.decodeEventLog(event_NFTDelisted, item.data, item.topics)
        printLog(`NFTDelisted@Block#${item.blockNumber} | Parameters: { NFTAddress:${data.NFTAddr}, tokenId: ${data.tokenId} } (${item.transactionHash})`)
      } if (eventId == event_NFTBought.topicHash) {
        const data = NFTMarket.interface.decodeEventLog(event_NFTBought, item.data, item.topics)
        printLog(`NFTBought@Block#${item.blockNumber} | Parameters: { NFTAddress:${data.NFTAddr}, tokenId: ${data.tokenId}, bidValue: ${data.bidValue} } (${item.transactionHash})`)
      }
    }
  }

  // ERC20-Permit(ERC2612) sign typed data
  const signPermit = async () => {
    const name = permit_Name.current?.value;
    const version = "1";
    const chainId = permit_ChainId.current?.value;
    const verifyingContract = permit_VerifyingContract.current?.value;
    const spender = permit_Spender.current?.value;
    const value = permit_ApprovedValue.current?.value;
    const deadline = permit_Deadline.current?.value;
    const signerAddress = permit_SignerAddr.current?.value;
    const provider = new ethers.BrowserProvider(window.ethereum)
    const signer = await provider.getSigner()
    const owner = await signer.getAddress();
    const tokenAddress = verifyingContract;
    const tokenAbi = ["function nonces(address owner) view returns (uint256)"];
    let tokenContract
    let nonce
    if (tokenAddress) {
      tokenContract = new ethers.Contract(tokenAddress, tokenAbi, provider);
      nonce = await tokenContract.nonces(signerAddress);
    } else {
      console.log("Invalid token address");
    }

    console.log(`signerAddress: ${signerAddress}`)
    console.log(`owner: ${owner}`)

    const domain = {
      name: name,
      version: version,
      chainId: chainId,
      verifyingContract: verifyingContract,
    };

    const types = {
      Permit: [
        { name: "owner", type: "address" },
        { name: "spender", type: "address" },
        { name: "value", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" }
      ],
    };

    const message = {
      owner: owner,
      spender: spender,
      value: value,
      nonce: nonce,
      deadline: deadline,
    };

    try {
      console.log(`Domin || name: ${domain.name}, version: ${domain.version}, chainId: ${domain.chainId}, verifyingContract: ${domain.verifyingContract}`)
      console.log("Types || Permit: ", JSON.stringify(types.Permit, null, 2));
      console.log(`message || owner: ${message.owner}, spender: ${message.spender}, value: ${message.value}, deadline: ${message.deadline}, nonce: ${message.nonce}`)
      console.log(`message: ${message}`)
      const signedMessage = await signer.signTypedData(domain, types, message);
      console.log("Signature:", signedMessage);
      const signatureResult = ethers.Signature.from(signedMessage);
      console.log("v: ", signatureResult.v);
      console.log("r: ", signatureResult.r);
      console.log("s: ", signatureResult.s);
    } catch (error) {
      console.error("Error signing permit:", error);
    }
  }

  // ERC721-Permit sign typed data
  const signNFTPermit = async () => {
    const name = permit_Name_NFT.current?.value;          // 不同：直接写死
    const version = "1";
    const chainId = permit_ChainId_NFT.current?.value;
    const verifyingContract = permit_VerifyingContract_NFT.current?.value;    // 不同：直接写死
    const buyer = permit_buyer_NFT.current?.value;
    const tokenId = permit_tokenId_NFT.current?.value;
    const deadline = permit_deadline_NFT.current?.value;
    const provider = new ethers.BrowserProvider(window.ethereum)
    const signer = await provider.getSigner()
    const signerAddress = await signer.getAddress();
    const tokenAddress = verifyingContract;
    const tokenAbi = ["function nonces(address owner) view returns (uint256)"];   // 不同：public、无 view
    let ERC721WithPermitContract
    let nonce
    if (tokenAddress) {
      ERC721WithPermitContract = new ethers.Contract(tokenAddress, tokenAbi, provider);
      nonce = await ERC721WithPermitContract.nonces(signerAddress);
    } else {
      console.log("Invalid token address");
    }

    const domain = {
      name: name,
      version: version,
      chainId: chainId,
      verifyingContract: verifyingContract,
    };

    const types = {
      NFTPermit: [
        { name: "buyer", type: "address" },
        { name: "tokenId", type: "uint256" },
        { name: "signerNonce", type: "uint256" },
        { name: "deadline", type: "uint256" }
      ],
    };

    const message = {
      buyer: buyer,
      tokenId: tokenId,
      signerNonce: nonce,
      deadline: deadline,
    };

    try {
      console.log(`ERC721WithPermitContract: ${ERC721WithPermitContract}, signerAddress: ${signerAddress}`);
      console.log(`Domin || name: ${domain.name}, typeof(name): ${typeof(domain.name)}`)
      console.log(`Domin || version: ${domain.version}, typeof(version): ${typeof(domain.version)}`)
      console.log(`Domin || chainId: ${domain.chainId}, typeof(chainId): ${typeof(domain.chainId)}`)
      console.log(`Domin || verifyingContract: ${domain.verifyingContract}, typeof(verifyingContract): ${typeof(domain.verifyingContract)}`)
      console.log("Types || NFTPermit: ", JSON.stringify(types.NFTPermit, null, 2))
      console.log(`message || buyer: ${message.buyer}, typeof(buyer): ${typeof(message.buyer)}`)
      console.log(`message || tokenId: ${message.tokenId}, typeof(tokenId): ${typeof(message.tokenId)}`)
      console.log(`message || signerNonce: ${message.signerNonce}, typeof(signerNonce): ${typeof(message.signerNonce)}`)
      console.log(`message || deadline: ${message.deadline}, typeof(deadline): ${typeof(message.deadline)}`)

      const signedMessage = await signer.signTypedData(domain, types, message);
      console.log("Signature(ERC721-Permit):", signedMessage);
      const signatureResult = ethers.Signature.from(signedMessage);
      console.log("v: ", signatureResult.v);
      console.log("r: ", signatureResult.r);
      console.log("s: ", signatureResult.s);
    } catch (error) {
      console.error("Error signing permit:", error);
    }
  }

  function printLog(msg: any) {
    let p = document.createElement("p");
    p.textContent = msg
    document.getElementsByClassName("logs")[0].appendChild(p)
  }

  const openTxUrl_List = () => {
    if (TxURL_List)
      window.open(TxURL_List, '_blank');
  };
  const openTxUrl_Deist = () => {
    if (TxURL_Delist)
      window.open(TxURL_Delist, '_blank');
  };
  const openTxUrl_Buy = () => {
    if (TxURL_Buy)
      window.open(TxURL_Buy, '_blank');
  };

  const handleConnect = async () => {
    setIsConnecting(true)
    try {
      const accounts: [] = await window.ethereum.request({
        method: "eth_requestAccounts",
      })
      let startBlockNumber = 45068820
      getLogs(startBlockNumber, startBlockNumber + 200)
      _updateState(accounts)
      setError(false)
    } catch (err: any) {
      setError(true)
      setErrorMessage(err.message)
    }
    setIsConnecting(false)
  }

  return (
    <div className="App">
      <h2>Garen NFTMarket</h2>
      <div>{window.ethereum?.isMetaMask && wallet.accounts.length < 1 &&
        <button disabled={disableConnect} style={{ fontSize: '22px' }} onClick={handleConnect}>Connect MetaMask</button>
      }</div>
      <div className="info-container" >
        {wallet.accounts.length > 0 &&
          <>
            <div>Wallet Accounts: {wallet.accounts[0]}</div>
            <div>Wallet Balance: {wallet.balance}</div>
            <div>ChainId: {wallet.chainId}</div>
            <div>Token(GTST) Balance: {GTTBalance} GTST</div>
          </>
        }
        {error && (
          <div style={{ fontSize: '18px', color: 'red' }} onClick={() => setError(false)}>
            <strong>Error:</strong> {errorMessage}
          </div>
        )
        }
      </div>
      <div className='InteractionArea'>
        {wallet.accounts.length > 0 && (
          <div className="left-container">


            {window.ethereum?.isMetaMask && wallet.accounts.length > 0 &&
              <>
                <label>NFT Address:</label>
                <input ref={NFTAddressRef_List} placeholder="Input NFT contract address" type="text" />
                <label>tokenId:</label>
                <input ref={tokenIdRef_List} placeholder="Input tokenId of NFT" type="text" />
                <label>price:</label>
                <input ref={NFTPriceRef_List} placeholder="Input theh price of listed NFT" type="text" />
                <button onClick={handleNFTMarket_List}>List NFT</button>
              </>
            }
            {
              isNFTMarketApproved == false &&
              <button style={{ fontSize: '14px' }} onClick={handleNFT_Approve}>Approve NFTMarket</button>
            }
            {TxURL_List != null &&
              <>
                <button id="TxOfList" v-show="TxURL_List" onClick={() => openTxUrl_List()}> Transaction </button>
              </>
            }
            <br />
            {window.ethereum?.isMetaMask && wallet.accounts.length > 0 &&
              <>
                <label>NFT Address:</label>
                <input ref={NFTAddressRef_Delist} placeholder="Input NFT contract address" type="text" />
                <label>tokenId:</label>
                <input ref={tokenIdRef_Delist} placeholder="Input tokenId of NFT" type="text" />
                <button onClick={handleNFTMarket_Delist}>Delist NFT</button>
              </>
            }
            {TxURL_Delist != null &&
              <>
                <button id="TxOfDelist" v-show="TxURL_Delist" onClick={() => openTxUrl_Deist()}> Transaction </button>
              </>
            }
            <br />
            {window.ethereum?.isMetaMask && wallet.accounts.length > 0 &&
              <>
                <label>NFT Address:</label>
                <input ref={NFTAddressRef_Buy} placeholder="Input NFT contract address" type="text" />
                <label>tokenId:</label>
                <input ref={tokenIdRef_Buy} placeholder="Input tokenId of NFT" type="text" />
                <label>bidValue:</label>
                <input ref={bidValueRef_Buy} placeholder="Input value of bidding" type="text" />
                <button onClick={handleNFTMarket_Buy}>Buy NFT</button>
              </>
            }
            {TxURL_Buy != null &&
              <>
                <button id="TxOfBuy" v-show="TxURL_Buy" onClick={() => openTxUrl_Buy()}> Transaction </button>
              </>
            }


            {/*
            <br />
            <h3 style={{ fontSize: '20px' }}>Create Signature for Permit(ERC20): </h3>
            {window.ethereum?.isMetaMask && wallet.accounts.length > 0 &&
              <>
                <label>Token Name:</label>
                <input ref={permit_Name} placeholder="Token Name" type="text" />
                <label>ChainId:</label>
                <input ref={permit_ChainId} placeholder="ChainId" type="text" />
                <label>Verifying Contract Address:</label>
                <input ref={permit_VerifyingContract} placeholder="Verifying Contract Address" type="text" />
                <label>Spender:</label>
                <input ref={permit_Spender} placeholder="Spender Address" type="text" />
                <label>Approved Value:</label>
                <input ref={permit_ApprovedValue} placeholder="Approved Value" type="text" />
                <label>Deadline:</label>
                <input ref={permit_Deadline} placeholder="Deadline" type="text" />
                <label>Signer's Address(Check Nonce):</label>
                <input ref={permit_SignerAddr} placeholder="Signer's Address" type="text" />
                <button onClick={signPermit}>SignTypedData</button>
              </>
            }
            <br />
            <h3 style={{ fontSize: '20px' }}>Create Signature for Permit(ERC721): </h3>
            {window.ethereum?.isMetaMask && wallet.accounts.length > 0 &&
              <>
                <label>Token Name:</label>
                <input ref={permit_Name_NFT} placeholder="Token Name" type="text" />
                <label>ChainId:</label>
                <input ref={permit_ChainId_NFT} placeholder="ChainId" type="text" />
                <label>Verifying Contract Address:</label>
                <input ref={permit_VerifyingContract_NFT} placeholder="Verifying Contract Address" type="text" />
                <label>Buyer:</label>
                <input ref={permit_buyer_NFT} placeholder="Buyer" type="text" />
                <label>tokenId:</label>
                <input ref={permit_tokenId_NFT} placeholder="tokenId" type="text" />
                <label>Deadline:</label>
                <input ref={permit_deadline_NFT} placeholder="Deadline" type="text" />
                <button onClick={signNFTPermit}>SignTypedData(For NFT)</button>
              </>
            }
          */}


          </div>
        )}
        {wallet.accounts.length > 0 && (
          <div className='right-container'>
            <h3>Listed NFTs : </h3>
            {Object.keys(ListedNFT).map((address) => (
              <div key={address}>
                <h4>{address}</h4>
                <ul>
                  {ListedNFT[address].map((nftInfo) => (
                    <li key={nftInfo.tokenId}>
                      Token ID: {nftInfo.tokenId},
                      Price in USD: {nftInfo.priceInUSD.toString()}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
            <h4 style={{ fontSize: '20px', color: 'gray', marginBottom: "3px" }}>Logs : </h4>
            {
              wallet.accounts.length > 0 && (
                <div className='logs' style={{ fontSize: '15px', color: 'gray' }}></div>
              )
            }
          </div>
        )}
      </div>

    </div>
  )
}

export default App