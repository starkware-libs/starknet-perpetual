use core::num::traits::Pow;
use perpetuals::core::components::positions::interface::{
    IPositionsDispatcher, IPositionsDispatcherTrait,
};
use perpetuals::core::interface::{ICoreDispatcher, ICoreDispatcherTrait, Settlement};
use perpetuals::core::types::asset::AssetIdTrait;
use perpetuals::core::types::asset::synthetic::SyntheticAsset;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::position::{PositionData, PositionId};
use perpetuals::core::types::price::Price;
use perpetuals::core::types::risk_factor::RiskFactorTrait;
use snforge_std::DeclareResultTrait;
use starknet::ContractAddress;
use starkware_utils::components::replaceability::interface::{
    IReplaceableDispatcher, IReplaceableDispatcherTrait, ImplementationData,
};
use starkware_utils::time::time::Timestamp;
use starkware_utils_testing::test_utils::cheat_caller_address_once;

fn replace_to_new_implementation() {
    let replaceability_dispatcher = IReplaceableDispatcher { contract_address: CONTRACT_ADDRESS };

    // Declare the new code.
    let core_contract = snforge_std::declare("Core").unwrap().contract_class();
    let new_class_hash = core_contract.class_hash;

    // Create the implementation data
    let implementation_data = ImplementationData {
        impl_hash: *new_class_hash, eic_data: None, final: false,
    };

    cheat_caller_address_once(contract_address: CONTRACT_ADDRESS, caller_address: UPGRADE_ADMIN);
    replaceability_dispatcher.add_new_implementation(implementation_data);

    cheat_caller_address_once(contract_address: CONTRACT_ADDRESS, caller_address: UPGRADE_ADMIN);
    replaceability_dispatcher.replace_to(implementation_data);
}

// These values are taken from the Mainnet deployment.
// Tx url:
// https://voyager.online/tx/0x277c2183c663ec87dd629f95dfdb763201d30d46ab11d9b89498712a482df36
const CONTRACT_ADDRESS: ContractAddress =
    0x062da0780fae50d68cecaa5a051606dc21217ba290969b302db4dd99d2e9b470
    .try_into()
    .unwrap();

const OPERATOR_ADDRESS: ContractAddress =
    0x048ddc53f41523d2a6b40c3dff7f69f4bbac799cd8b2e3fc50d3de1d4119441f
    .try_into()
    .unwrap();

const UPGRADE_ADMIN: ContractAddress =
    0x0522e5ba327bfbd85138b29bde060a5340a460706b00ae2e10e6d2a16fbf8c57
    .try_into()
    .unwrap();

// State of the positions:
// These states were taken from the Mainnet deployment on an old commit, 815283c, before the
// optimizations.

fn INIT_POSITION_DATA_A() -> PositionData {
    PositionData {
        synthetics: array![
            SyntheticAsset {
                id: AssetIdTrait::new(370321410161845694364216165796937728),
                balance: 277450_i64.into(),
                price: Price { value: 19255832311784 },
                risk_factor: RiskFactorTrait::new(50),
            },
        ]
            .span(),
        collateral_balance: (-14374401741_i64).into(),
    }
}

fn INIT_POSITION_DATA_B() -> PositionData {
    PositionData {
        synthetics: array![
            SyntheticAsset {
                id: AssetIdTrait::new(344400637349001255728961162330505216),
                balance: 277310_i64.into(),
                price: Price { value: 29850357691999 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(359977924063000458297011360688504832),
                balance: (-372580_i64).into(),
                price: Price { value: 115814026946606 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344278863660798979802850626929426432),
                balance: 5503090_i64.into(),
                price: Price { value: 22923160380348 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432690441716627433572355962568704000),
                balance: (-33990_i64).into(),
                price: Price { value: 89130868334500 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396323605930722754555422238098587648),
                balance: (-493090_i64).into(),
                price: Price { value: 30022563113048 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(411778891792336016648512811332272128),
                balance: (-958100_i64).into(),
                price: Price { value: 25844448804365 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(338883663474438343746899177019277312),
                balance: 279340_i64.into(),
                price: Price { value: 22337409713883 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432568984945910917982054318042251264),
                balance: (-1534190_i64).into(),
                price: Price { value: 56347501773664 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(411817625024622139428925067103305728),
                balance: 1405570_i64.into(),
                price: Price { value: 19129670170757 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458591633377628216554099757268598784),
                balance: 67350_i64.into(),
                price: Price { value: 75899949331905 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(354684143347689286618180522700963840),
                balance: 285918_i64.into(),
                price: Price { value: 58076191535549 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453216002551035381248377800238301184),
                balance: (-56230_i64).into(),
                price: Price { value: 21481117735452 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339167696437051981397172032081231872),
                balance: (-3790600_i64).into(),
                price: Price { value: 13398687807097 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453276691323521307730974454904258560),
                balance: (-169860_i64).into(),
                price: Price { value: 23733246167796 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339248760150559911178053148269871104),
                balance: (-1558380_i64).into(),
                price: Price { value: 66953174522527 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396101380212403101135280116273774592),
                balance: (-432280_i64).into(),
                price: Price { value: 62631450117141 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437823079767580094335063891128614912),
                balance: (-14576_i64).into(),
                price: Price { value: 90534757690763 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(338824487460085561411166284290195456),
                balance: (-1147540_i64).into(),
                price: Price { value: 85013150795457 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401334549526471356934815741500194816),
                balance: 27350_i64.into(),
                price: Price { value: 44664975523840 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(417113878881044044170394349040828416),
                balance: 36903108_i64.into(),
                price: Price { value: 1013708360542 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(364785659509114736355216580319117312),
                balance: 783050_i64.into(),
                price: Price { value: 21583121168596 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(431877150642355703025313311742754816),
                balance: (-32936_i64).into(),
                price: Price { value: 82636615561504 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(370321410161845694364216165796937728),
                balance: (-3148400_i64).into(),
                price: Price { value: 19255832311784 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401415448619475043208479622807158784),
                balance: (-31574_i64).into(),
                price: Price { value: 35589803123461 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416992418108949182116875998607704064),
                balance: (-1346660_i64).into(),
                price: Price { value: 6781953975595 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(390746430762672347138718348219514880),
                balance: 513690_i64.into(),
                price: Price { value: 27864385211229 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437822852025511902434950189083000832),
                balance: (-75280_i64).into(),
                price: Price { value: 225548380846135 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(370260563196593831237922481296637952),
                balance: 442601_i64.into(),
                price: Price { value: 22133845524480 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344097595806435454645696181259206656),
                balance: 25180_i64.into(),
                price: Price { value: 61859713616156 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437761440258352922500030743109959680),
                balance: (-651280_i64).into(),
                price: Price { value: 84312548267628 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396000038112596647361460946256003072),
                balance: (-3874970_i64).into(),
                price: Price { value: 32255901439281 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(375656867931341909315028931361898496),
                balance: (-10288240_i64).into(),
                price: Price { value: 11976627451635 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(385960324586951584765944650413375488),
                balance: 1382680_i64.into(),
                price: Price { value: 13400297963493 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(448024668544195796360802891422760960),
                balance: 1102500_i64.into(),
                price: Price { value: 28552908385130 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919616426605400900257294843904),
                balance: (-2290882_i64).into(),
                price: Price { value: 5524425411489 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437477565754482165017662333485318144),
                balance: (-178960_i64).into(),
                price: Price { value: 86513674983413 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401212385921352564110845035577081856),
                balance: 282133_i64.into(),
                price: Price { value: 52478082065367 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416789435879299995223824283975286784),
                balance: (-105490_i64).into(),
                price: Price { value: 122099451655566 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(359855675003405245145646005674311680),
                balance: (-243548_i64).into(),
                price: Price { value: 186786609264328 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432365923161760081025958177373421568),
                balance: 206909_i64.into(),
                price: Price { value: 76381590380078 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437638715834618327041098343530889216),
                balance: 136870_i64.into(),
                price: Price { value: 43168232014400 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432670881640427675234041645227835392),
                balance: (-300952_i64).into(),
                price: Price { value: 32762711217268 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416789436818522072078212394507042816),
                balance: 3040834_i64.into(),
                price: Price { value: 8263733792426 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(442933058567680452956063953642848256),
                balance: (-149410_i64).into(),
                price: Price { value: 25427040018625 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(380625508329364671305743144700608512),
                balance: 1188530_i64.into(),
                price: Price { value: 8615263651600 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919636945194886730150859243520),
                balance: 1527285_i64.into(),
                price: Price { value: 3321688114912 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(427174429141597609995520190256775168),
                balance: 109136_i64.into(),
                price: Price { value: 38598334218240 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(380663843873413173657742089127985152),
                balance: 544210_i64.into(),
                price: Price { value: 212266460126982 },
                risk_factor: RiskFactorTrait::new(500),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919633304379671818952480129024),
                balance: 8778558_i64.into(),
                price: Price { value: 2634232075833 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432590218091046889185300129471528960),
                balance: 247140_i64.into(),
                price: Price { value: 29966117877737 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339128557725978860634015450544472064),
                balance: 437570_i64.into(),
                price: Price { value: 11527701278802 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(468915544507303112068184696028135424),
                balance: (-319179_i64).into(),
                price: Price { value: 19649082389423 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(349553874717371921940984895618678784),
                balance: (-667420_i64).into(),
                price: Price { value: 20490610713322 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458550751644561930336286859415519232),
                balance: 145399_i64.into(),
                price: Price { value: 160521192199946 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453276858440817581570030792557461504),
                balance: (-379757_i64).into(),
                price: Price { value: 60772419828187 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401395555207980563015918882817835008),
                balance: 3160_i64.into(),
                price: Price { value: 29979539348520 },
                risk_factor: RiskFactorTrait::new(50),
            },
        ]
            .span(),
        collateral_balance: 4711960480526_i64.into(),
    }
}

fn STAGE_1_POSITION_DATA_A() -> PositionData {
    PositionData {
        synthetics: array![
            SyntheticAsset {
                id: AssetIdTrait::new(370321410161845694364216165796937728),
                balance: 283620_i64.into(),
                price: Price { value: 19255832311784 },
                risk_factor: RiskFactorTrait::new(50),
            },
        ]
            .span(),
        collateral_balance: (-14816890278_i64).into(),
    }
}

fn STAGE_1_POSITION_DATA_B() -> PositionData {
    PositionData {
        synthetics: array![
            SyntheticAsset {
                id: AssetIdTrait::new(344400637349001255728961162330505216),
                balance: 277310_i64.into(),
                price: Price { value: 29850357691999 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(359977924063000458297011360688504832),
                balance: (-372580_i64).into(),
                price: Price { value: 115814026946606 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344278863660798979802850626929426432),
                balance: 5503090_i64.into(),
                price: Price { value: 22923160380348 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432690441716627433572355962568704000),
                balance: (-33990_i64).into(),
                price: Price { value: 89130868334500 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396323605930722754555422238098587648),
                balance: (-493090_i64).into(),
                price: Price { value: 30022563113048 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(411778891792336016648512811332272128),
                balance: (-958100_i64).into(),
                price: Price { value: 25844448804365 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(338883663474438343746899177019277312),
                balance: 279340_i64.into(),
                price: Price { value: 22337409713883 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432568984945910917982054318042251264),
                balance: (-1534190_i64).into(),
                price: Price { value: 56347501773664 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(411817625024622139428925067103305728),
                balance: 1405570_i64.into(),
                price: Price { value: 19129670170757 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458591633377628216554099757268598784),
                balance: 67350_i64.into(),
                price: Price { value: 75899949331905 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(354684143347689286618180522700963840),
                balance: 285918_i64.into(),
                price: Price { value: 58076191535549 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453216002551035381248377800238301184),
                balance: (-56230_i64).into(),
                price: Price { value: 21481117735452 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339167696437051981397172032081231872),
                balance: (-3790600_i64).into(),
                price: Price { value: 13398687807097 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453276691323521307730974454904258560),
                balance: (-169860_i64).into(),
                price: Price { value: 23733246167796 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339248760150559911178053148269871104),
                balance: (-1558380_i64).into(),
                price: Price { value: 66953174522527 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396101380212403101135280116273774592),
                balance: (-432280_i64).into(),
                price: Price { value: 62631450117141 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437823079767580094335063891128614912),
                balance: (-14576_i64).into(),
                price: Price { value: 90534757690763 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(338824487460085561411166284290195456),
                balance: (-1147540_i64).into(),
                price: Price { value: 85013150795457 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401334549526471356934815741500194816),
                balance: 27350_i64.into(),
                price: Price { value: 44664975523840 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(417113878881044044170394349040828416),
                balance: 36903108_i64.into(),
                price: Price { value: 1013708360542 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(364785659509114736355216580319117312),
                balance: 783050_i64.into(),
                price: Price { value: 21583121168596 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(431877150642355703025313311742754816),
                balance: (-32936_i64).into(),
                price: Price { value: 82636615561504 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(370321410161845694364216165796937728),
                balance: (-3154570_i64).into(),
                price: Price { value: 19255832311784 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401415448619475043208479622807158784),
                balance: (-31574_i64).into(),
                price: Price { value: 35589803123461 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416992418108949182116875998607704064),
                balance: (-1346660_i64).into(),
                price: Price { value: 6781953975595 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(390746430762672347138718348219514880),
                balance: 513690_i64.into(),
                price: Price { value: 27864385211229 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437822852025511902434950189083000832),
                balance: (-75280_i64).into(),
                price: Price { value: 225548380846135 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(370260563196593831237922481296637952),
                balance: 442601_i64.into(),
                price: Price { value: 22133845524480 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344097595806435454645696181259206656),
                balance: 25180_i64.into(),
                price: Price { value: 61859713616156 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437761440258352922500030743109959680),
                balance: (-651280_i64).into(),
                price: Price { value: 84312548267628 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396000038112596647361460946256003072),
                balance: (-3874970_i64).into(),
                price: Price { value: 32255901439281 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(375656867931341909315028931361898496),
                balance: (-10288240_i64).into(),
                price: Price { value: 11976627451635 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(385960324586951584765944650413375488),
                balance: 1382680_i64.into(),
                price: Price { value: 13400297963493 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(448024668544195796360802891422760960),
                balance: 1102500_i64.into(),
                price: Price { value: 28552908385130 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919616426605400900257294843904),
                balance: (-2290882_i64).into(),
                price: Price { value: 5524425411489 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437477565754482165017662333485318144),
                balance: (-178960_i64).into(),
                price: Price { value: 86513674983413 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401212385921352564110845035577081856),
                balance: 282133_i64.into(),
                price: Price { value: 52478082065367 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416789435879299995223824283975286784),
                balance: (-105490_i64).into(),
                price: Price { value: 122099451655566 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(359855675003405245145646005674311680),
                balance: (-243548_i64).into(),
                price: Price { value: 186786609264328 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432365923161760081025958177373421568),
                balance: 206909_i64.into(),
                price: Price { value: 76381590380078 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437638715834618327041098343530889216),
                balance: 136870_i64.into(),
                price: Price { value: 43168232014400 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432670881640427675234041645227835392),
                balance: (-300952_i64).into(),
                price: Price { value: 32762711217268 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416789436818522072078212394507042816),
                balance: 3040834_i64.into(),
                price: Price { value: 8263733792426 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(442933058567680452956063953642848256),
                balance: (-149410_i64).into(),
                price: Price { value: 25427040018625 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(380625508329364671305743144700608512),
                balance: 1188530_i64.into(),
                price: Price { value: 8615263651600 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919636945194886730150859243520),
                balance: 1527285_i64.into(),
                price: Price { value: 3321688114912 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(427174429141597609995520190256775168),
                balance: 109136_i64.into(),
                price: Price { value: 38598334218240 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(380663843873413173657742089127985152),
                balance: 544210_i64.into(),
                price: Price { value: 212266460126982 },
                risk_factor: RiskFactorTrait::new(500),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919633304379671818952480129024),
                balance: 8778558_i64.into(),
                price: Price { value: 2634232075833 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432590218091046889185300129471528960),
                balance: 247140_i64.into(),
                price: Price { value: 29966117877737 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339128557725978860634015450544472064),
                balance: 437570_i64.into(),
                price: Price { value: 11527701278802 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(468915544507303112068184696028135424),
                balance: (-319179_i64).into(),
                price: Price { value: 19649082389423 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(349553874717371921940984895618678784),
                balance: (-667420_i64).into(),
                price: Price { value: 20490610713322 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458550751644561930336286859415519232),
                balance: 145399_i64.into(),
                price: Price { value: 160521192199946 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453276858440817581570030792557461504),
                balance: (-379757_i64).into(),
                price: Price { value: 60772419828187 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401395555207980563015918882817835008),
                balance: 3160_i64.into(),
                price: Price { value: 29979539348520 },
                risk_factor: RiskFactorTrait::new(50),
            },
        ]
            .span(),
        collateral_balance: 4712402869526_i64.into(),
    }
}

fn STAGE_2_POSITION_DATA_A() -> PositionData {
    PositionData {
        synthetics: array![
            SyntheticAsset {
                id: AssetIdTrait::new(416789436818522072078212394507042816),
                balance: 3121_i64.into(),
                price: Price { value: 8263733792426 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416992418108949182116875998607704064),
                balance: 3610_i64.into(),
                price: Price { value: 6781953975595 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432690441716627433572355962568704000),
                balance: (-470_i64).into(),
                price: Price { value: 89130868334500 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396000038112596647361460946256003072),
                balance: (-610_i64).into(),
                price: Price { value: 32255901439281 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432568984945910917982054318042251264),
                balance: 1020_i64.into(),
                price: Price { value: 56347501773664 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(370321410161845694364216165796937728),
                balance: (-5790_i64).into(),
                price: Price { value: 19255832311784 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339167696437051981397172032081231872),
                balance: 2700_i64.into(),
                price: Price { value: 13398687807097 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432365923161760081025958177373421568),
                balance: (-39_i64).into(),
                price: Price { value: 76381590380078 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(417113878881044044170394349040828416),
                balance: (-2195_i64).into(),
                price: Price { value: 1013708360542 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(364785659509114736355216580319117312),
                balance: 420_i64.into(),
                price: Price { value: 21583121168596 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(385960324586951584765944650413375488),
                balance: (-6870_i64).into(),
                price: Price { value: 13400297963493 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(380663843873413173657742089127985152),
                balance: 50_i64.into(),
                price: Price { value: 212266460126982 },
                risk_factor: RiskFactorTrait::new(100),
            },
        ]
            .span(),
        collateral_balance: 4082472867_i64.into(),
    }
}

fn STAGE_2_POSITION_DATA_B() -> PositionData {
    PositionData {
        synthetics: array![
            SyntheticAsset {
                id: AssetIdTrait::new(359977924063000458297011360688504832),
                balance: (-150_i64).into(),
                price: Price { value: 115814026946606 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344400637349001255728961162330505216),
                balance: 490_i64.into(),
                price: Price { value: 29850357691999 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344278863660798979802850626929426432),
                balance: (-150_i64).into(),
                price: Price { value: 22923160380348 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432690441716627433572355962568704000),
                balance: (-70_i64).into(),
                price: Price { value: 89130868334500 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396323605930722754555422238098587648),
                balance: 730_i64.into(),
                price: Price { value: 30022563113048 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(411778891792336016648512811332272128),
                balance: (-260_i64).into(),
                price: Price { value: 25844448804365 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(338883663474438343746899177019277312),
                balance: (-580_i64).into(),
                price: Price { value: 22337409713883 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432568984945910917982054318042251264),
                balance: 130_i64.into(),
                price: Price { value: 56347501773664 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(411817625024622139428925067103305728),
                balance: 740_i64.into(),
                price: Price { value: 19129670170757 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458591633377628216554099757268598784),
                balance: 210_i64.into(),
                price: Price { value: 75899949331905 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(354684143347689286618180522700963840),
                balance: (-180_i64).into(),
                price: Price { value: 58076191535549 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453216002551035381248377800238301184),
                balance: 160_i64.into(),
                price: Price { value: 21481117735452 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339167696437051981397172032081231872),
                balance: (-1580_i64).into(),
                price: Price { value: 13398687807097 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453276691323521307730974454904258560),
                balance: (-490_i64).into(),
                price: Price { value: 23733246167796 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339248760150559911178053148269871104),
                balance: 160_i64.into(),
                price: Price { value: 66953174522527 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396101380212403101135280116273774592),
                balance: 50_i64.into(),
                price: Price { value: 62631450117141 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437823079767580094335063891128614912),
                balance: 290_i64.into(),
                price: Price { value: 90534757690763 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(359998998794517018713123529349398528),
                balance: (-2750_i64).into(),
                price: Price { value: 31390104027136 },
                risk_factor: RiskFactorTrait::new(5),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(417113878881044044170394349040828416),
                balance: 11600_i64.into(),
                price: Price { value: 1013708360542 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(364785659509114736355216580319117312),
                balance: (-320_i64).into(),
                price: Price { value: 21583121168596 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437761440258352922500030743109959680),
                balance: 300_i64.into(),
                price: Price { value: 84312548267628 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(370321410161845694364216165796937728),
                balance: (-570_i64).into(),
                price: Price { value: 19255832311784 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(385960324586951584765944650413375488),
                balance: 1420_i64.into(),
                price: Price { value: 13400297963493 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(448024668544195796360802891422760960),
                balance: (-80_i64).into(),
                price: Price { value: 28552908385130 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919616426605400900257294843904),
                balance: (-3100_i64).into(),
                price: Price { value: 5524425411489 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(370260563196593831237922481296637952),
                balance: 670_i64.into(),
                price: Price { value: 22133845524480 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(338824487460085561411166284290195456),
                balance: 220_i64.into(),
                price: Price { value: 85013150795457 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416789435879299995223824283975286784),
                balance: (-380_i64).into(),
                price: Price { value: 122099451655566 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(375656867931341909315028931361898496),
                balance: (-2080_i64).into(),
                price: Price { value: 11976627451635 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432365923161760081025958177373421568),
                balance: 160_i64.into(),
                price: Price { value: 76381590380078 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437638715834618327041098343530889216),
                balance: 1010_i64.into(),
                price: Price { value: 43168232014400 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(380625508329364671305743144700608512),
                balance: 3010_i64.into(),
                price: Price { value: 8615263651600 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401334549526471356934815741500194816),
                balance: 510_i64.into(),
                price: Price { value: 44664975523840 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919636945194886730150859243520),
                balance: 7700_i64.into(),
                price: Price { value: 3321688114912 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416789436818522072078212394507042816),
                balance: (-2000_i64).into(),
                price: Price { value: 8263733792426 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437477565754482165017662333485318144),
                balance: (-70_i64).into(),
                price: Price { value: 86513674983413 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396000038112596647361460946256003072),
                balance: 750_i64.into(),
                price: Price { value: 32255901439281 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(390746430762672347138718348219514880),
                balance: 100_i64.into(),
                price: Price { value: 27864385211229 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344097595806435454645696181259206656),
                balance: 10_i64.into(),
                price: Price { value: 61859713616156 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437822852025511902434950189083000832),
                balance: 80_i64.into(),
                price: Price { value: 225548380846135 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432670881640427675234041645227835392),
                balance: 780_i64.into(),
                price: Price { value: 32762711217268 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(431877150642355703025313311742754816),
                balance: 120_i64.into(),
                price: Price { value: 82636615561504 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(427174429141597609995520190256775168),
                balance: 570_i64.into(),
                price: Price { value: 38598334218240 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458247228599093253039736795210711040),
                balance: (-3460_i64).into(),
                price: Price { value: 93835640176640 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401415448619475043208479622807158784),
                balance: (-30_i64).into(),
                price: Price { value: 35589803123461 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458267273324209361917147961830146048),
                balance: (-660_i64).into(),
                price: Price { value: 183301151129600 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432590218096110157059814614722674688),
                balance: 1600_i64.into(),
                price: Price { value: 173311325634560 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416992418108949182116875998607704064),
                balance: (-1640_i64).into(),
                price: Price { value: 6781953975595 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(380663843873413173657742089127985152),
                balance: 10_i64.into(),
                price: Price { value: 212266460126982 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919633304379671818952480129024),
                balance: 8000_i64.into(),
                price: Price { value: 2634232075833 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401212385921352564110845035577081856),
                balance: 470_i64.into(),
                price: Price { value: 52478082065367 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(442933058567680452956063953642848256),
                balance: (-640_i64).into(),
                price: Price { value: 25427040018625 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432590218091046889185300129471528960),
                balance: 290_i64.into(),
                price: Price { value: 29966117877737 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339128557725978860634015450544472064),
                balance: (-290_i64).into(),
                price: Price { value: 11527701278802 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(349553874717371921940984895618678784),
                balance: 1280_i64.into(),
                price: Price { value: 20490610713322 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453276858440817581570030792557461504),
                balance: (-230_i64).into(),
                price: Price { value: 60772419828187 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401395555207980563015918882817835008),
                balance: (-740_i64).into(),
                price: Price { value: 29979539348520 },
                risk_factor: RiskFactorTrait::new(50),
            },
        ]
            .span(),
        collateral_balance: 2820087134_i64.into(),
    }
}

fn STAGE_3_POSITION_DATA_A() -> PositionData {
    PositionData {
        synthetics: array![
            SyntheticAsset {
                id: AssetIdTrait::new(344400637349001255728961162330505216),
                balance: 277310_i64.into(),
                price: Price { value: 29850357691999 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(359977924063000458297011360688504832),
                balance: (-372580_i64).into(),
                price: Price { value: 115814026946606 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344278863660798979802850626929426432),
                balance: 5503090_i64.into(),
                price: Price { value: 22923160380348 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432690441716627433572355962568704000),
                balance: (-33990_i64).into(),
                price: Price { value: 89130868334500 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396323605930722754555422238098587648),
                balance: (-493090_i64).into(),
                price: Price { value: 30022563113048 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(411778891792336016648512811332272128),
                balance: (-957840_i64).into(),
                price: Price { value: 25844448804365 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(338883663474438343746899177019277312),
                balance: 279340_i64.into(),
                price: Price { value: 22337409713883 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432568984945910917982054318042251264),
                balance: (-1534190_i64).into(),
                price: Price { value: 56347501773664 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(411817625024622139428925067103305728),
                balance: 1405570_i64.into(),
                price: Price { value: 19129670170757 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458591633377628216554099757268598784),
                balance: 67350_i64.into(),
                price: Price { value: 75899949331905 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(354684143347689286618180522700963840),
                balance: 285918_i64.into(),
                price: Price { value: 58076191535549 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453216002551035381248377800238301184),
                balance: (-56230_i64).into(),
                price: Price { value: 21481117735452 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339167696437051981397172032081231872),
                balance: (-3790600_i64).into(),
                price: Price { value: 13398687807097 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453276691323521307730974454904258560),
                balance: (-169860_i64).into(),
                price: Price { value: 23733246167796 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339248760150559911178053148269871104),
                balance: (-1558380_i64).into(),
                price: Price { value: 66953174522527 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396101380212403101135280116273774592),
                balance: (-432280_i64).into(),
                price: Price { value: 62631450117141 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437823079767580094335063891128614912),
                balance: (-14576_i64).into(),
                price: Price { value: 90534757690763 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(338824487460085561411166284290195456),
                balance: (-1147540_i64).into(),
                price: Price { value: 85013150795457 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401334549526471356934815741500194816),
                balance: 27350_i64.into(),
                price: Price { value: 44664975523840 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(417113878881044044170394349040828416),
                balance: 36903108_i64.into(),
                price: Price { value: 1013708360542 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(364785659509114736355216580319117312),
                balance: 783050_i64.into(),
                price: Price { value: 21583121168596 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(431877150642355703025313311742754816),
                balance: (-32936_i64).into(),
                price: Price { value: 82636615561504 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(370321410161845694364216165796937728),
                balance: (-3154570_i64).into(),
                price: Price { value: 19255832311784 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401415448619475043208479622807158784),
                balance: (-31574_i64).into(),
                price: Price { value: 35589803123461 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416992418108949182116875998607704064),
                balance: (-1346660_i64).into(),
                price: Price { value: 6781953975595 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(390746430762672347138718348219514880),
                balance: 513690_i64.into(),
                price: Price { value: 27864385211229 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437822852025511902434950189083000832),
                balance: (-75280_i64).into(),
                price: Price { value: 225548380846135 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(370260563196593831237922481296637952),
                balance: 442601_i64.into(),
                price: Price { value: 22133845524480 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344097595806435454645696181259206656),
                balance: 25180_i64.into(),
                price: Price { value: 61859713616156 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437761440258352922500030743109959680),
                balance: (-651280_i64).into(),
                price: Price { value: 84312548267628 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396000038112596647361460946256003072),
                balance: (-3874970_i64).into(),
                price: Price { value: 32255901439281 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(375656867931341909315028931361898496),
                balance: (-10288240_i64).into(),
                price: Price { value: 11976627451635 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(385960324586951584765944650413375488),
                balance: 1382680_i64.into(),
                price: Price { value: 13400297963493 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(448024668544195796360802891422760960),
                balance: 1102500_i64.into(),
                price: Price { value: 28552908385130 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919616426605400900257294843904),
                balance: (-2290882_i64).into(),
                price: Price { value: 5524425411489 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437477565754482165017662333485318144),
                balance: (-178960_i64).into(),
                price: Price { value: 86513674983413 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401212385921352564110845035577081856),
                balance: 282133_i64.into(),
                price: Price { value: 52478082065367 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416789435879299995223824283975286784),
                balance: (-105490_i64).into(),
                price: Price { value: 122099451655566 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(359855675003405245145646005674311680),
                balance: (-243548_i64).into(),
                price: Price { value: 186786609264328 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432365923161760081025958177373421568),
                balance: 206909_i64.into(),
                price: Price { value: 76381590380078 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437638715834618327041098343530889216),
                balance: 136870_i64.into(),
                price: Price { value: 43168232014400 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432670881640427675234041645227835392),
                balance: (-300952_i64).into(),
                price: Price { value: 32762711217268 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416789436818522072078212394507042816),
                balance: 3040834_i64.into(),
                price: Price { value: 8263733792426 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(442933058567680452956063953642848256),
                balance: (-149410_i64).into(),
                price: Price { value: 25427040018625 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(380625508329364671305743144700608512),
                balance: 1188530_i64.into(),
                price: Price { value: 8615263651600 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919636945194886730150859243520),
                balance: 1527285_i64.into(),
                price: Price { value: 3321688114912 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(427174429141597609995520190256775168),
                balance: 109136_i64.into(),
                price: Price { value: 38598334218240 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(380663843873413173657742089127985152),
                balance: 544210_i64.into(),
                price: Price { value: 212266460126982 },
                risk_factor: RiskFactorTrait::new(500),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919633304379671818952480129024),
                balance: 8778558_i64.into(),
                price: Price { value: 2634232075833 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432590218091046889185300129471528960),
                balance: 247140_i64.into(),
                price: Price { value: 29966117877737 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339128557725978860634015450544472064),
                balance: 437570_i64.into(),
                price: Price { value: 11527701278802 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(468915544507303112068184696028135424),
                balance: (-319179_i64).into(),
                price: Price { value: 19649082389423 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(349553874717371921940984895618678784),
                balance: (-667420_i64).into(),
                price: Price { value: 20490610713322 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458550751644561930336286859415519232),
                balance: 145399_i64.into(),
                price: Price { value: 160521192199946 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453276858440817581570030792557461504),
                balance: (-379757_i64).into(),
                price: Price { value: 60772419828187 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401395555207980563015918882817835008),
                balance: 3160_i64.into(),
                price: Price { value: 29979539348520 },
                risk_factor: RiskFactorTrait::new(50),
            },
        ]
            .span(),
        collateral_balance: 4712377787326_i64.into(),
    }
}

fn STAGE_3_POSITION_DATA_B() -> PositionData {
    PositionData {
        synthetics: array![
            SyntheticAsset {
                id: AssetIdTrait::new(359977924063000458297011360688504832),
                balance: (-150_i64).into(),
                price: Price { value: 115814026946606 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344400637349001255728961162330505216),
                balance: 490_i64.into(),
                price: Price { value: 29850357691999 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344278863660798979802850626929426432),
                balance: (-150_i64).into(),
                price: Price { value: 22923160380348 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432690441716627433572355962568704000),
                balance: (-70_i64).into(),
                price: Price { value: 89130868334500 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396323605930722754555422238098587648),
                balance: 730_i64.into(),
                price: Price { value: 30022563113048 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(411778891792336016648512811332272128),
                balance: (-520_i64).into(),
                price: Price { value: 25844448804365 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(338883663474438343746899177019277312),
                balance: (-580_i64).into(),
                price: Price { value: 22337409713883 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432568984945910917982054318042251264),
                balance: 130_i64.into(),
                price: Price { value: 56347501773664 },
                risk_factor: RiskFactorTrait::new(10),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(411817625024622139428925067103305728),
                balance: 740_i64.into(),
                price: Price { value: 19129670170757 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458591633377628216554099757268598784),
                balance: 210_i64.into(),
                price: Price { value: 75899949331905 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(354684143347689286618180522700963840),
                balance: (-180_i64).into(),
                price: Price { value: 58076191535549 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453216002551035381248377800238301184),
                balance: 160_i64.into(),
                price: Price { value: 21481117735452 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339167696437051981397172032081231872),
                balance: (-1580_i64).into(),
                price: Price { value: 13398687807097 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453276691323521307730974454904258560),
                balance: (-490_i64).into(),
                price: Price { value: 23733246167796 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339248760150559911178053148269871104),
                balance: 160_i64.into(),
                price: Price { value: 66953174522527 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396101380212403101135280116273774592),
                balance: 50_i64.into(),
                price: Price { value: 62631450117141 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437823079767580094335063891128614912),
                balance: 290_i64.into(),
                price: Price { value: 90534757690763 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(359998998794517018713123529349398528),
                balance: (-2750_i64).into(),
                price: Price { value: 31390104027136 },
                risk_factor: RiskFactorTrait::new(5),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(417113878881044044170394349040828416),
                balance: 11600_i64.into(),
                price: Price { value: 1013708360542 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(364785659509114736355216580319117312),
                balance: (-320_i64).into(),
                price: Price { value: 21583121168596 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437761440258352922500030743109959680),
                balance: 300_i64.into(),
                price: Price { value: 84312548267628 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(370321410161845694364216165796937728),
                balance: (-570_i64).into(),
                price: Price { value: 19255832311784 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(385960324586951584765944650413375488),
                balance: 1420_i64.into(),
                price: Price { value: 13400297963493 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(448024668544195796360802891422760960),
                balance: (-80_i64).into(),
                price: Price { value: 28552908385130 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919616426605400900257294843904),
                balance: (-3100_i64).into(),
                price: Price { value: 5524425411489 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(370260563196593831237922481296637952),
                balance: 670_i64.into(),
                price: Price { value: 22133845524480 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(338824487460085561411166284290195456),
                balance: 220_i64.into(),
                price: Price { value: 85013150795457 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416789435879299995223824283975286784),
                balance: (-380_i64).into(),
                price: Price { value: 122099451655566 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(375656867931341909315028931361898496),
                balance: (-2080_i64).into(),
                price: Price { value: 11976627451635 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432365923161760081025958177373421568),
                balance: 160_i64.into(),
                price: Price { value: 76381590380078 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437638715834618327041098343530889216),
                balance: 1010_i64.into(),
                price: Price { value: 43168232014400 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(380625508329364671305743144700608512),
                balance: 3010_i64.into(),
                price: Price { value: 8615263651600 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401334549526471356934815741500194816),
                balance: 510_i64.into(),
                price: Price { value: 44664975523840 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919636945194886730150859243520),
                balance: 7700_i64.into(),
                price: Price { value: 3321688114912 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416789436818522072078212394507042816),
                balance: (-2000_i64).into(),
                price: Price { value: 8263733792426 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437477565754482165017662333485318144),
                balance: (-70_i64).into(),
                price: Price { value: 86513674983413 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(396000038112596647361460946256003072),
                balance: 750_i64.into(),
                price: Price { value: 32255901439281 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(390746430762672347138718348219514880),
                balance: 100_i64.into(),
                price: Price { value: 27864385211229 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(344097595806435454645696181259206656),
                balance: 10_i64.into(),
                price: Price { value: 61859713616156 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(437822852025511902434950189083000832),
                balance: 80_i64.into(),
                price: Price { value: 225548380846135 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432670881640427675234041645227835392),
                balance: 780_i64.into(),
                price: Price { value: 32762711217268 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(431877150642355703025313311742754816),
                balance: 120_i64.into(),
                price: Price { value: 82636615561504 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(427174429141597609995520190256775168),
                balance: 570_i64.into(),
                price: Price { value: 38598334218240 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458247228599093253039736795210711040),
                balance: (-3460_i64).into(),
                price: Price { value: 93835640176640 },
                risk_factor: RiskFactorTrait::new(20),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401415448619475043208479622807158784),
                balance: (-30_i64).into(),
                price: Price { value: 35589803123461 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(458267273324209361917147961830146048),
                balance: (-660_i64).into(),
                price: Price { value: 183301151129600 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432590218096110157059814614722674688),
                balance: 1600_i64.into(),
                price: Price { value: 173311325634560 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(416992418108949182116875998607704064),
                balance: (-1640_i64).into(),
                price: Price { value: 6781953975595 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(380663843873413173657742089127985152),
                balance: 10_i64.into(),
                price: Price { value: 212266460126982 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(255399919633304379671818952480129024),
                balance: 8000_i64.into(),
                price: Price { value: 2634232075833 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401212385921352564110845035577081856),
                balance: 470_i64.into(),
                price: Price { value: 52478082065367 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(442933058567680452956063953642848256),
                balance: (-640_i64).into(),
                price: Price { value: 25427040018625 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(432590218091046889185300129471528960),
                balance: 290_i64.into(),
                price: Price { value: 29966117877737 },
                risk_factor: RiskFactorTrait::new(50),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(339128557725978860634015450544472064),
                balance: (-290_i64).into(),
                price: Price { value: 11527701278802 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(349553874717371921940984895618678784),
                balance: 1280_i64.into(),
                price: Price { value: 20490610713322 },
                risk_factor: RiskFactorTrait::new(30),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(453276858440817581570030792557461504),
                balance: (-230_i64).into(),
                price: Price { value: 60772419828187 },
                risk_factor: RiskFactorTrait::new(100),
            },
            SyntheticAsset {
                id: AssetIdTrait::new(401395555207980563015918882817835008),
                balance: (-740_i64).into(),
                price: Price { value: 29979539348520 },
                risk_factor: RiskFactorTrait::new(50),
            },
        ]
            .span(),
        collateral_balance: 2845163064_i64.into(),
    }
}

const INIT_TV_POSITION_A: i128 = 1483931588831941904;
const INIT_TR_POSITION_A: u128 = 267126533745223540;

const INIT_TV_POSITION_B: i128 = 845625941873142417799;
const INIT_TR_POSITION_B: u128 = 121641466619609476513;

const STAGE_1_TV_POSITION_A: i128 = 1483960461991281312;
const STAGE_1_TR_POSITION_A: u128 = 273066958013408904;

const STAGE_1_TV_POSITION_B: i128 = 845625886280723094519;
const STAGE_1_TR_POSITION_B: u128 = 121653347468145847241;

const STAGE_2_TV_POSITION_A: i128 = 989160679498475036;
const STAGE_2_TR_POSITION_A: u128 = 17317382345531754;

const STAGE_2_TV_POSITION_B: i128 = 736319576937788404;
const STAGE_2_TR_POSITION_B: u128 = 67490499962362629;

const STAGE_3_TV_POSITION_A: i128 = 845625872885617746219;
const STAGE_3_TR_POSITION_A: u128 = 121653145881445173194;

const STAGE_3_TV_POSITION_B: i128 = 736331288952827584;
const STAGE_3_TR_POSITION_B: u128 = 67692086663036676;


#[test]
#[fork(url: "https://rpc.starknet.lava.build/", block_number: 1978107)]
fn test_mainnet_data_thress_trades() {
    // Setup:
    let core_dispatcher = ICoreDispatcher { contract_address: CONTRACT_ADDRESS };
    let positions_dispatcher = IPositionsDispatcher { contract_address: CONTRACT_ADDRESS };

    // Replace:
    replace_to_new_implementation();

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x31357 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x31357 });

    assert_eq!(position_data, INIT_POSITION_DATA_A());

    assert_eq!(tv_tr.total_value, INIT_TV_POSITION_A);
    assert_eq!(tv_tr.total_risk, INIT_TR_POSITION_A);

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x1f4 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x1f4 });

    assert_eq!(position_data, INIT_POSITION_DATA_B());

    assert_eq!(tv_tr.total_value, INIT_TV_POSITION_B);
    assert_eq!(tv_tr.total_risk, INIT_TR_POSITION_B);

    cheat_caller_address_once(contract_address: CONTRACT_ADDRESS, caller_address: OPERATOR_ADDRESS);
    core_dispatcher
        .trade(
            operator_nonce: 0x590178,
            signature_a: array![
                0x79efd35a94a5d01bc32f2d77a1d02148039d9ba2bff6fbfd9038d403107fb37,
                0x331559dfad6df7627fb6ad6e6bf4c0609f9250bd56b96c3f33b359d335a1fb0,
            ]
                .span(),
            signature_b: array![
                0x517e3a8def3b9e71e1653c224cef7d7f289f4e961babdb19b5f2997a7f0423b,
                0xb6d637a145ca0c11a026f6b040d64842ba6eaac5bd0be0a01b8f0fc02e4e9a,
            ]
                .span(),
            order_a: Order {
                position_id: PositionId { value: 0x31357 },
                base_asset_id: AssetIdTrait::new(0x47524153532d310000000000000000),
                base_amount: 0x5a550.try_into().unwrap(),
                quote_asset_id: AssetIdTrait::new(0x1),
                quote_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffff3a6d1ea41
                    .try_into()
                    .unwrap(),
                fee_asset_id: AssetIdTrait::new(0x1),
                fee_amount: 0xb6157f.try_into().unwrap(),
                expiration: Timestamp { seconds: 0x69411c56 },
                salt: 0x1c9012f3,
            },
            order_b: Order {
                position_id: PositionId { value: 0x1f4 },
                base_asset_id: AssetIdTrait::new(0x47524153532d310000000000000000),
                base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffc2e1d
                    .try_into()
                    .unwrap(),
                quote_asset_id: AssetIdTrait::new(0x1),
                quote_amount: 0x42dddc5d0.try_into().unwrap(),
                fee_asset_id: AssetIdTrait::new(0x1),
                fee_amount: 0x88f161.try_into().unwrap(),
                expiration: Timestamp { seconds: 0x68ca6cd4 },
                salt: 0x43cb5fd4,
            },
            actual_amount_base_a: 0x181a.try_into().unwrap(),
            actual_amount_quote_a: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffe5a1adf9
                .try_into()
                .unwrap(),
            actual_fee_a: 0x184d1.try_into().unwrap(),
            actual_fee_b: 0,
        );

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x31357 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x31357 });

    assert_eq!(position_data, STAGE_1_POSITION_DATA_A());

    assert_eq!(tv_tr.total_value, STAGE_1_TV_POSITION_A);
    assert_eq!(tv_tr.total_risk, STAGE_1_TR_POSITION_A);

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x1f4 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x1f4 });

    assert_eq!(position_data, STAGE_1_POSITION_DATA_B());

    assert_eq!(tv_tr.total_value, STAGE_1_TV_POSITION_B);
    assert_eq!(tv_tr.total_risk, STAGE_1_TR_POSITION_B);

    // Trade 2:

    cheat_caller_address_once(contract_address: CONTRACT_ADDRESS, caller_address: OPERATOR_ADDRESS);
    core_dispatcher
        .trade(
            operator_nonce: 0x590179,
            signature_a: array![
                0x19b1c7ac98001e7088afab360d8fa836bf64ef8cf6a39f4809c9d0da7746422,
                0x4aa37e0fdfd590fd065d11da324cd85cfbb37125c134a9c050d25f30cc2d0a0,
            ]
                .span(),
            signature_b: array![
                0x9394f56dc7346d0986e43ae77df98b3ff4d4aa89da12d3f06f6809ceb55bd2,
                0x385aa2e614c1ac9b110da393bcbbf56a8e64f6fc38b3fd2e6dcad9c00dffcf5,
            ]
                .span(),
            order_a: Order {
                position_id: PositionId { value: 0x19905 },
                base_asset_id: AssetIdTrait::new(0x5345492d3000000000000000000000),
                base_amount: 0x212.try_into().unwrap(),
                quote_asset_id: AssetIdTrait::new(0x1),
                quote_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffff70226f5
                    .try_into()
                    .unwrap(),
                fee_asset_id: AssetIdTrait::new(0x1),
                fee_amount: 0, // 0xb6157f
                expiration: Timestamp { seconds: 0x68ca7aad },
                salt: 0xfc98573b,
            },
            order_b: Order {
                position_id: PositionId { value: 0x1f9 },
                base_asset_id: AssetIdTrait::new(0x5345492d3000000000000000000000),
                base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffeb7
                    .try_into()
                    .unwrap(),
                quote_asset_id: AssetIdTrait::new(0x1),
                quote_amount: 0x5971c74.try_into().unwrap(),
                fee_asset_id: AssetIdTrait::new(0x1),
                fee_amount: 0xb72f.try_into().unwrap(),
                expiration: Timestamp { seconds: 0x68ca6cd8 },
                salt: 0x20023f2e,
            },
            actual_amount_base_a: 0x14a.try_into().unwrap(),
            actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffa66c625
                .try_into()
                .unwrap(),
            actual_fee_a: 0,
            actual_fee_b: 0x5bb9.try_into().unwrap(),
        );

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x19905 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x19905 });

    assert_eq!(position_data, STAGE_2_POSITION_DATA_A());

    assert_eq!(tv_tr.total_value, STAGE_2_TV_POSITION_A);
    assert_eq!(tv_tr.total_risk, STAGE_2_TR_POSITION_A);

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x1f9 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x1f9 });

    assert_eq!(position_data, STAGE_2_POSITION_DATA_B());

    assert_eq!(tv_tr.total_value, STAGE_2_TV_POSITION_B);
    assert_eq!(tv_tr.total_risk, STAGE_2_TR_POSITION_B);

    // Trade 3:

    cheat_caller_address_once(contract_address: CONTRACT_ADDRESS, caller_address: OPERATOR_ADDRESS);
    core_dispatcher
        .trade(
            operator_nonce: 0x59017a,
            signature_a: array![
                0x46c193585dbb7636bd548999a92d8f079ebb2f5a7a32e7c7c83fd78f0282373,
                0x5e00816fad9e842e51c86d58b0d6c8e62ecb9c0aeedc5add38e5ee00898ec4e,
            ]
                .span(),
            signature_b: array![
                0x1a5946390580cdef0031142b2314268ee6ae444ccb5afcc9ac8bc9d79a13a15,
                0x6d15be97d8c3955f2337a38c963fdff07f17364d0b6437d4de28fe6c46d1a91,
            ]
                .span(),
            order_a: Order {
                position_id: PositionId { value: 0x1f4 },
                base_asset_id: AssetIdTrait::new(0x4f4e444f2d31000000000000000000),
                base_amount: 0xead76.try_into().unwrap(),
                quote_asset_id: AssetIdTrait::new(0x1),
                quote_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffea64f5af5d
                    .try_into()
                    .unwrap(),
                fee_asset_id: AssetIdTrait::new(0x1),
                fee_amount: 0x2c3f921.try_into().unwrap(),
                expiration: Timestamp { seconds: 0x68ca6cd9 },
                salt: 0x2d07228f,
            },
            order_b: Order {
                position_id: PositionId { value: 0x1f9 },
                base_asset_id: AssetIdTrait::new(0x4f4e444f2d31000000000000000000),
                base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffefd
                    .try_into()
                    .unwrap(),
                quote_asset_id: AssetIdTrait::new(0x1),
                quote_amount: 0x17e0288.try_into().unwrap(),
                fee_asset_id: AssetIdTrait::new(0x1),
                fee_amount: 0x30e6.try_into().unwrap(),
                expiration: Timestamp { seconds: 0x68ca6cda },
                salt: 0x3f211f2d,
            },
            actual_amount_base_a: 0x104.try_into().unwrap(),
            actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffe8146a9
                .try_into()
                .unwrap(),
            actual_fee_a: 0,
            actual_fee_b: 0x187e.try_into().unwrap(),
        );

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x1f4 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x1f4 });

    assert_eq!(position_data, STAGE_3_POSITION_DATA_A());

    assert_eq!(tv_tr.total_value, STAGE_3_TV_POSITION_A);
    assert_eq!(tv_tr.total_risk, STAGE_3_TR_POSITION_A);

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x1f9 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x1f9 });

    assert_eq!(position_data, STAGE_3_POSITION_DATA_B());

    assert_eq!(tv_tr.total_value, STAGE_3_TV_POSITION_B);
    assert_eq!(tv_tr.total_risk, STAGE_3_TR_POSITION_B);
}

#[test]
#[fork(url: "https://rpc.starknet.lava.build/", block_number: 1978107)]
fn test_mainnet_data_multi_trade() {
    // Setup:
    let core_dispatcher = ICoreDispatcher { contract_address: CONTRACT_ADDRESS };
    let positions_dispatcher = IPositionsDispatcher { contract_address: CONTRACT_ADDRESS };

    // Replace:
    replace_to_new_implementation();

    // Check the initial state:
    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x31357 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x31357 });

    assert_eq!(position_data, INIT_POSITION_DATA_A());

    assert_eq!(tv_tr.total_value, INIT_TV_POSITION_A);
    assert_eq!(tv_tr.total_risk, INIT_TR_POSITION_A);

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x1f4 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x1f4 });

    assert_eq!(position_data, INIT_POSITION_DATA_B());

    assert_eq!(tv_tr.total_value, INIT_TV_POSITION_B);
    assert_eq!(tv_tr.total_risk, INIT_TR_POSITION_B);

    // Execute the multi-trade:
    cheat_caller_address_once(contract_address: CONTRACT_ADDRESS, caller_address: OPERATOR_ADDRESS);
    core_dispatcher
        .multi_trade(
            operator_nonce: 0x590178,
            trades: array![
                // Trade 1:
                Settlement {
                    signature_a: array![
                        0x79efd35a94a5d01bc32f2d77a1d02148039d9ba2bff6fbfd9038d403107fb37,
                        0x331559dfad6df7627fb6ad6e6bf4c0609f9250bd56b96c3f33b359d335a1fb0,
                    ]
                        .span(),
                    signature_b: array![
                        0x517e3a8def3b9e71e1653c224cef7d7f289f4e961babdb19b5f2997a7f0423b,
                        0xb6d637a145ca0c11a026f6b040d64842ba6eaac5bd0be0a01b8f0fc02e4e9a,
                    ]
                        .span(),
                    order_a: Order {
                        position_id: PositionId { value: 0x31357 },
                        base_asset_id: AssetIdTrait::new(0x47524153532d310000000000000000),
                        base_amount: 370000,
                        quote_asset_id: AssetIdTrait::new(0x1),
                        quote_amount: -53035800000,
                        fee_asset_id: AssetIdTrait::new(0x1),
                        fee_amount: 11933055,
                        expiration: Timestamp { seconds: 0x69411c56 },
                        salt: 0x1c9012f3,
                    },
                    order_b: Order {
                        position_id: PositionId { value: 0x1f4 },
                        base_asset_id: AssetIdTrait::new(0x47524153532d310000000000000000),
                        base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffc2e1d
                            .try_into()
                            .unwrap(),
                        quote_asset_id: AssetIdTrait::new(0x1),
                        quote_amount: 0x42dddc5d0.try_into().unwrap(),
                        fee_asset_id: AssetIdTrait::new(0x1),
                        fee_amount: 0x88f161.try_into().unwrap(),
                        expiration: Timestamp { seconds: 0x68ca6cd4 },
                        salt: 0x43cb5fd4,
                    },
                    actual_amount_base_a: 0x181a.try_into().unwrap(),
                    actual_amount_quote_a: 0x800000000000010ffffffffffffffffffffffffffffffffffffffffe5a1adf9
                        .try_into()
                        .unwrap(),
                    actual_fee_a: 0x184d1.try_into().unwrap(),
                    actual_fee_b: 0,
                },
                // Trade 2:
                Settlement {
                    signature_a: array![
                        0x19b1c7ac98001e7088afab360d8fa836bf64ef8cf6a39f4809c9d0da7746422,
                        0x4aa37e0fdfd590fd065d11da324cd85cfbb37125c134a9c050d25f30cc2d0a0,
                    ]
                        .span(),
                    signature_b: array![
                        0x9394f56dc7346d0986e43ae77df98b3ff4d4aa89da12d3f06f6809ceb55bd2,
                        0x385aa2e614c1ac9b110da393bcbbf56a8e64f6fc38b3fd2e6dcad9c00dffcf5,
                    ]
                        .span(),
                    order_a: Order {
                        position_id: PositionId { value: 0x19905 },
                        base_asset_id: AssetIdTrait::new(0x5345492d3000000000000000000000),
                        base_amount: 0x212.try_into().unwrap(),
                        quote_asset_id: AssetIdTrait::new(0x1),
                        quote_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffff70226f5
                            .try_into()
                            .unwrap(),
                        fee_asset_id: AssetIdTrait::new(0x1),
                        fee_amount: 0, // 0xb6157f
                        expiration: Timestamp { seconds: 0x68ca7aad },
                        salt: 0xfc98573b,
                    },
                    order_b: Order {
                        position_id: PositionId { value: 0x1f9 },
                        base_asset_id: AssetIdTrait::new(0x5345492d3000000000000000000000),
                        base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffeb7
                            .try_into()
                            .unwrap(),
                        quote_asset_id: AssetIdTrait::new(0x1),
                        quote_amount: 0x5971c74.try_into().unwrap(),
                        fee_asset_id: AssetIdTrait::new(0x1),
                        fee_amount: 0xb72f.try_into().unwrap(),
                        expiration: Timestamp { seconds: 0x68ca6cd8 },
                        salt: 0x20023f2e,
                    },
                    actual_amount_base_a: 0x14a.try_into().unwrap(),
                    actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffa66c625
                        .try_into()
                        .unwrap(),
                    actual_fee_a: 0,
                    actual_fee_b: 0x5bb9.try_into().unwrap(),
                },
                // Trade 3:
                Settlement {
                    signature_a: array![
                        0x46c193585dbb7636bd548999a92d8f079ebb2f5a7a32e7c7c83fd78f0282373,
                        0x5e00816fad9e842e51c86d58b0d6c8e62ecb9c0aeedc5add38e5ee00898ec4e,
                    ]
                        .span(),
                    signature_b: array![
                        0x1a5946390580cdef0031142b2314268ee6ae444ccb5afcc9ac8bc9d79a13a15,
                        0x6d15be97d8c3955f2337a38c963fdff07f17364d0b6437d4de28fe6c46d1a91,
                    ]
                        .span(),
                    order_a: Order {
                        position_id: PositionId { value: 0x1f4 },
                        base_asset_id: AssetIdTrait::new(0x4f4e444f2d31000000000000000000),
                        base_amount: 0xead76.try_into().unwrap(),
                        quote_asset_id: AssetIdTrait::new(0x1),
                        quote_amount: 0x800000000000010ffffffffffffffffffffffffffffffffffffffea64f5af5d
                            .try_into()
                            .unwrap(),
                        fee_asset_id: AssetIdTrait::new(0x1),
                        fee_amount: 0x2c3f921.try_into().unwrap(),
                        expiration: Timestamp { seconds: 0x68ca6cd9 },
                        salt: 0x2d07228f,
                    },
                    order_b: Order {
                        position_id: PositionId { value: 0x1f9 },
                        base_asset_id: AssetIdTrait::new(0x4f4e444f2d31000000000000000000),
                        base_amount: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffffffefd
                            .try_into()
                            .unwrap(),
                        quote_asset_id: AssetIdTrait::new(0x1),
                        quote_amount: 0x17e0288.try_into().unwrap(),
                        fee_asset_id: AssetIdTrait::new(0x1),
                        fee_amount: 0x30e6.try_into().unwrap(),
                        expiration: Timestamp { seconds: 0x68ca6cda },
                        salt: 0x3f211f2d,
                    },
                    actual_amount_base_a: 0x104.try_into().unwrap(),
                    actual_amount_quote_a: 0x800000000000010fffffffffffffffffffffffffffffffffffffffffe8146a9
                        .try_into()
                        .unwrap(),
                    actual_fee_a: 0,
                    actual_fee_b: 0x187e.try_into().unwrap(),
                },
            ]
                .span(),
        );

    // Check the final state of the 4 positions:

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x31357 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x31357 });

    assert_eq!(position_data, STAGE_1_POSITION_DATA_A());

    assert_eq!(tv_tr.total_value, STAGE_1_TV_POSITION_A);
    assert_eq!(tv_tr.total_risk, STAGE_1_TR_POSITION_A);

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x1f4 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x1f4 });

    assert_eq!(position_data, STAGE_3_POSITION_DATA_A());

    assert_eq!(tv_tr.total_value, STAGE_3_TV_POSITION_A);
    assert_eq!(tv_tr.total_risk, STAGE_3_TR_POSITION_A);

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x19905 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x19905 });

    assert_eq!(position_data, STAGE_2_POSITION_DATA_A());

    assert_eq!(tv_tr.total_value, STAGE_2_TV_POSITION_A);
    assert_eq!(tv_tr.total_risk, STAGE_2_TR_POSITION_A);

    let tv_tr = positions_dispatcher.get_position_tv_tr(position_id: PositionId { value: 0x1f9 });
    let position_data = positions_dispatcher
        .get_position_assets(position_id: PositionId { value: 0x1f9 });

    assert_eq!(position_data, STAGE_3_POSITION_DATA_B());

    assert_eq!(tv_tr.total_value, STAGE_3_TV_POSITION_B);
    assert_eq!(tv_tr.total_risk, STAGE_3_TR_POSITION_B);
}

