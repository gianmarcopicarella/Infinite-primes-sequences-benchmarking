
{-# LANGUAGE DeriveGeneric        #-}
{-# OPTIONS_GHC -Wall             #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

{-|

  Module      : AutoBench.Internal.Types
  Description : Datatypes and associated helper functions\/defaults.
  Copyright   : (c) 2018 Martin Handley
  License     : BSD-style
  Maintainer  : martin.handley@nottingham.ac.uk
  Stability   : Experimental
  Portability : GHC

  Datatypes used throughout AutoBench's implementation and any associated 
  helper functions\/defaults.

-}

{-
   ----------------------------------------------------------------------------
   <TO-DO>:
   ----------------------------------------------------------------------------
   - 'DataOpts' Discover setting;
   - Split Types into InternalTypes and Types;
   - Make AnalOpts in TestSuite a maybe type? In case users don't want to 
     analyse right away;
   - Comment docTestSuite, docUserInputs;
   - 
-}

module AutoBench.Internal.Types 
  (

  -- * User inputs
  -- ** Test suites
    TestSuite(..)          -- Test suites are AutoBench's principle user input datatype.
  , docTestSuite           -- Generate a 'PP.Doc' for a 'TestSuite'.
  -- ** Test data options
  , UnaryTestData          -- User-specified test data for unary test programs.
  , BinaryTestData         -- User-specified test data for binary test programs.
  , DataOpts(..)           -- Test data options.
  , toHRange               -- Convert @Gen l s u :: DataOpts@ to a Haskell range.
  , minInputs              -- Minimum number of distinctly sized test inputs.
  , defBenchRepFilename    -- Default benchmarking JSON report filename.
  -- ** Statistical analysis options
  , AnalOpts(..)           -- Statistical analysis options.
  , maxPredictors          -- Maximum number of predictors for models to be used for regression analysis.         
  , minCVTrain             -- Minimum percentage of data set to use for cross-validation.
  , maxCVTrain             -- Maximum percentage of data set to use for cross-validation.
  , minCVIters             -- Minimum number of cross-validation iterations.
  , maxCVIters             -- Maximum number of cross-validation iterations.
  -- ** Internal representation of user inputs
  , UserInputs(..)         -- A data structure maintained by the system to classify user inputs.
  , docUserInputs          -- Create a 'PP.Doc' for a 'UserInputs'.
  , initUserInputs         -- Initialise a 'UserInputs' data structure.
  -- * Benchmarking
  -- * Statistical analysis
  , LinearType(..)                                                                                      -- <TO-DO>
  , Stats(..)                                                                                           -- <TO-DO>
  , numPredictors          --  Number of predictors for each type of model.
  -- * Errors
  -- ** System errors
  , SystemError(..)        -- System errors.
  -- ** Input errors
  , InputError(..)         -- User input errors.

  ) where

import           Control.DeepSeq           (NFData)
import           Control.Exception.Base    (Exception)
import qualified Criterion.Types           as Criterion
import qualified Criterion.Main            as Criterion
import           Data.Default              (Default(..))
import           Data.List                 (sort)
import           GHC.Generics              (Generic)
import qualified Text.PrettyPrint.HughesPJ as PP

import AutoBench.Internal.Utils (deggar, subNum, superNum)
import AutoBench.Internal.AbstractSyntax 
  ( HsType
  , Id
  , ModuleElem(..)
  , TypeString
  , prettyPrint
  )

-- To be able to DeepSeq CR.Config add NFData instances:
instance NFData Criterion.Verbosity
instance NFData Criterion.Config

-- * User inputs

-- ** Test suites

-- | Test suites are AutoBench's principle user input datatype, and are used to 
-- structure performance tests into logical units that can be checked, 
-- validated, and executed independently. 
--
-- An advantage of this approach is that users can group multiple test 
-- suites in the same file according to some testing context, whether it be 
-- analysing the performance of the same programs subject to different levels 
-- of optimisation, or comparing different implementations under the same
-- test conditions. Another advantage is that if one or more test suites in an 
-- input file are erroneous, other, valid test suites in the same file can be 
-- executed nonetheless.
--
-- Test suites contain a significant number of user options and settings. As 
-- such, the system provides the following defaults,
--
-- @ TestSuite
--     { _progs    = []                                     -- All programs in the test file will be considered for test purposes.
--     , _dataOpts = def                                    -- See 'DataOpts'.
--     , _analOpts = def                                    -- See 'AnalOpts'.
--     , _critCfg  = Criterion.Main.Options.defaultConfig   -- See 'Criterion.Main.Options.defaultConfig'
--     , _baseline = False                                  -- No baseline measurements.
--     , _nf       = True                                   -- Evaluate test cases to normal form.
--     , _ghcFlags = []                                     --/No optimisation, i.e., -O0.
--     }
-- @
--
-- that users can override.
--
-- Important note: the most basic check that the system performs on every test
-- suite is to ensure that each of its record fields are initialised: please
-- ensure test suites are fully defined.
data TestSuite = 
  TestSuite
    {  _progs    :: [Id]             -- ^ Identifiers of programs in the input file to test: note all programs
                                     --   in the file will be considered if this list is empty.
    , _dataOpts :: DataOpts          -- ^ Test data options ('DataOpts').
    , _analOpts :: AnalOpts          -- ^ Statistical analysis options ('AnalOpts').
    , _critCfg  :: Criterion.Config  -- ^ Criterion's configuration ('Criterion.Types.Config').
    , _baseline :: Bool              -- ^ Whether the graphs of runtime results should include baseline measurements.
    , _nf       :: Bool              -- ^ Whether test cases should be evaluated to nf (@True@) or whnf (@False@).
    , _ghcFlags :: [String]          -- ^ GHC compiler flags used when compiling files compiling benchmarks.
    } deriving (Generic)

instance Default TestSuite where 
  def = TestSuite
          { _progs    = []                         -- All programs in the test file will be considered for test purposes.           
          , _dataOpts = def                        -- See 'DataOpts'. 
          , _analOpts = def                        -- See 'AnalOpts'.        
          , _critCfg  = Criterion.defaultConfig    -- See 'Criterion.Main.Options.defaultConfig'
          , _baseline = False                      -- No baseline measurements.
          , _nf       = True                       -- Evaluate test cases to normal form.
          , _ghcFlags = []                         -- No optimisation, i.e., -O0. 
          }
  
instance NFData TestSuite 
instance Show TestSuite where 
  show = PP.render . docTestSuite

-- ** Test data options

-- | @type UnaryTestData a = [(Int, IO a)]@.
--
-- Due to certain benchmarking requirements, test data must be specified in 
-- the IO monad. In addition, the system cannot determine the size of 
-- user-specified test data automatically. As such, for a test program 
-- @p :: a -> b@ , user-specified test data is of type @[(Int, IO a)]@, where 
-- the first element of each tuple is the size of the test input, and the second 
-- element is the input itself. 
--
-- Concrete example: test program @p :: [Int] -> [Int]@, user-specified test 
-- data @tDat@.
--
-- @ tDat :: UnaryTestData [Int]
-- tDat = 
--   [ ( 5
--     , return [1,2,3,4,5] 
--     )
--   , ( 10 
--     , return [1,2,3,4,5,6,7,8,9,10] 
--     )
--   ... ]@
-- 
-- Here the size of each @[Int]@ is determined by its number of elements 
-- (@5@ and @10@, respectively).
--
-- Note: test suites require a minimum number of /distinctly sized/ test 
-- inputs: see 'minInputs'.
-- 
-- __**Incorrectly sized test data will lead to erroneous performance results**__.
type UnaryTestData a = [(Int, IO a)]  

-- | @type BinaryTestData a b = [(Int, Int, IO a, IO b)]@
--
-- See 'UnaryTestData' for a discussion on user-specified test data and a
-- relevant example for unary test programs. This example generalises to
-- user-specified test data for binary test programs in the obvious way:
-- 
-- @tDat :: BinaryTestData [Char] [Int]
-- tDat = 
--   [ ( 5
--     , 4
--     , return [/'a/', /'b/', /'c/', /'d/', /'e/']
--     , return [0, 1, 2, 3] )
--   , ( 10 
--     , 9
--     , return [/'a/', /'b/', /'c/', /'d/', /'e/', /'f/', /'g/', /'h/', /'i/', /'j/'] )
--     , return [0, 1, 2, 3, 4, 5, 6, 7, 8]
--   ... ]@
--
-- 'TestSuite's require a minimum number of /distinctly sized/ test datums: see 
-- 'minInputs'. In the case of 'BinaryTestData', /pairs/ of sizes must be 
-- distinct. For example, @(5, 4)@ and @(10, 9)@ above are two distinct pairs of 
-- sizes.
--
-- __**Incorrectly sized test data will lead to invalid performance results**__.
type BinaryTestData a b = [(Int, Int, IO a, IO b)]

-- | Test data can either be specified by users or generated automatically by 
-- the system. Note: the default setting for 'DataOpts' is @Gen 5 5 100@.
--
-- If users choose to specify their own inputs, then the 'Manual' data option 
-- simply tells the system the name of the test data in the user input file.
-- For example: 
--
-- @ module UserInput where 
--
-- tProg :: [Int] -> [Int]
-- tProg  = ...
--
-- tDat :: UnaryTestData [Int]
-- tDat  = ...
--
-- ts :: TestSuite 
-- ts  = def { _progs = ["tProg"], _dataOpts = Manual "tDat" }
-- @
--
-- See 'UnaryTestData' and 'BinaryTestData' for details regarding the /types/ 
-- of user-specified test data. 
--
-- If test data should be generated by the system, users must specify the size 
-- of the data to be generated. This is achieved using @Gen l s u@, 
-- which specifies as a size /range/ by a lower bound @l@, an upper bound 
-- @u@, and a step @s@. This is converted to a Haskell range 
-- @[l, (l + s) .. u]@ and a test input is generated for each size in this
-- list. 
-- For example: @Gen 5 5 100@ corresponds to the range @[5, 10, 15 .. 100]@. 
--
-- 'TestSuite's require a minimum number of /distinctly sized/ inputs: see 
-- 'minInputs'.
--
-- __**Incorrectly sized test data will lead to erroneous performance results**__.
data DataOpts = 
    Manual Id           -- ^ The system should search for user-specified test data
                        --   with the given name in the user input file.
  | Gen Int Int Int     -- ^ The system should generate random test data in the given size range.
 -- | Discover          -- ^ <TO-DO>: The system should discover compatible user-specified 
                        -- data, or accept a suitable 'Gen' setting at a later time.
    deriving (Eq, Generic)

instance NFData DataOpts 

instance Show DataOpts where 
  show (Manual idt) = "Manual " ++ "\"" ++ idt ++ "\""
  show (Gen l s u)  = "Gen " ++ show l ++ " " ++ show s  ++ " " ++ show u

instance Default DataOpts where 
  def = Gen 5 5 100

-- | Convert @Gen l s u :: DataOpts@ to a Haskell range.
toHRange :: DataOpts -> [Int]
toHRange Manual{}    = []
toHRange (Gen l s u) = [l, (l + s) .. u]

-- | Each test suite requires a minimum number of distinctly sized test inputs.
-- 
-- > minInputs = 20
minInputs :: Int 
minInputs  = 20

-- | Default benchmarking JSON report filename.
defBenchRepFilename :: String
defBenchRepFilename  = "autobench_tmp.json"

-- ** Statistical analysis options

-- | User options for statistical analysis.                                                                  -- ** NEEDS COMMENTS ** 
data AnalOpts = 
  AnalOpts
    { 
    -- Models to fit:
      _linearModels  :: [LinearType]                                    -- ^ Models for linear regression analysis.

    -- Cross-validation:
    , _cvIters       :: Int                                             -- ^ Number of cross-validation iterations.
    , _cvTrain       :: Double                                          -- ^ Percentage of data set to use for cross-validation 
                                                                        --   training; the rest is used for validation.
    -- Model comparison:
    , _topModels     :: Int                                             -- ^ The top n models to review.
    , _statsFilt     :: Stats -> Bool                                   -- ^ Function to discard models that \"do not\" fit a given data set.
    , _statsSort     :: Stats -> Stats -> Ordering                      -- ^ Function to select a model that \"best fits\" a given data set.
    -- Calculating efficiency results:
    , _runtimeComp   :: Double -> Double -> Ordering                    -- ^ Function to compare runtimes of test programs.
    , _runtimeOrd    :: [Ordering] -> Maybe (Ordering, Double)          -- ^ Function to calculate an efficiency ordering from ordered runtimes.
    -- Results generated by the system:
    , _graphFP       :: Maybe FilePath                                  -- ^ Graph of runtime results.
    , _reportFP      :: Maybe FilePath                                  -- ^ Report of results.
    , _coordsFP      :: Maybe FilePath                                  -- ^ CSV of (input size(s), runtime) coordinates.
    } deriving (Generic)

instance NFData AnalOpts 

instance Default AnalOpts where
  def = AnalOpts
          {
            _linearModels  = fmap Poly [0..4] ++ [Log 2 1, Log 2 2, PolyLog 2 1, Exp 2]
          , _cvIters       = 100
          , _cvTrain       = 0.7
          , _topModels     = 1
          , _statsFilt     = const True                                                                           --  <TO-DO>
          , _statsSort     = (\_ _ -> EQ)                                                                         --  <TO-DO>
          , _runtimeComp   = (\_ _ -> EQ)                                                                         --  <TO-DO>
          , _runtimeOrd    = const Nothing                                                                        --  <TO-DO>
          , _graphFP       = Just "./TimeChecked.png"  
          , _reportFP      = Nothing                   
          , _coordsFP      = Nothing
          }

-- | Maximum number of predictors for models to be used for regression analysis.
--
-- > maxPredictors = 10
maxPredictors :: Int 
maxPredictors  = 10

-- | Minimum percentage of data set to use for cross-validation.
--
-- > minCVTrain = 0.5
minCVTrain :: Double 
minCVTrain  = 0.5

-- | Maximum percentage of data set to use for cross-validation.
--
-- > maxCVTrain = 0.8
maxCVTrain :: Double 
maxCVTrain  = 0.8

-- | Minimum number of cross-validation iterations.
--
-- > minCVIters = 100
minCVIters :: Int 
minCVIters  = 100

-- | Maximum number of cross-validation iterations.
--
-- > maxCVIters = 500
maxCVIters :: Int 
maxCVIters  = 500

-- ** Internal representation of user inputs

-- | While user inputs are being analysed by the system, a 'UserInputs' data
-- structure is maintained. The purpose of this data structure is to classify 
-- user inputs according to the properties they satisfy. For example, when the 
-- system first interprets a user input file, all of its definitions are added 
-- to the '_allElems' list. This list is then processed to determine which 
-- definitions have function types that are syntactically compatible with the 
-- requirements of the system (see 'AutoBench.Internal.StaticChecks'). 
-- Definitions that are compatible are added to the '_validElems' list, and 
-- those that aren't are added to the '_invalidElems' list. Elements in the 
-- '_validElems' list are then classified according to, for example, whether 
-- they are nullary, unary, or binary functions. This check process continues
-- until all user  inputs are classified according to the list headers below. 
-- Note that both static ('AutoBench.Internal.StaticChecks') and dynamic 
-- ('AutoBench.Internal.DynamicChecks') checks are required to classify user 
-- inputs.
--
-- Notice that each /invalid/ definitions has one or more input errors 
-- associated with it.
--
-- After the system has processed all user inputs, users can review this data 
-- structure to see how the system has classified their inputs, and if any 
-- input errors have been generated. 
data UserInputs = 
  UserInputs
   {
     _allElems           :: [(ModuleElem, Maybe TypeString)]         -- ^ All definitions in a user input file.
   , _invalidElems       :: [(ModuleElem, Maybe TypeString)]         -- ^ Syntactically invalid definitions (see 'AutoBench.Internal.AbstractSyntax').
   , _validElems         :: [(Id, HsType)]                           -- ^ Syntactically valid definitions (see 'AutoBench.Internal.AbstractSyntax').
   , _nullaryFuns        :: [(Id, HsType)]                           -- ^ Nullary functions.
   , _unaryFuns          :: [(Id, HsType)]                           -- ^ Unary functions.
   , _binaryFuns         :: [(Id, HsType)]                           -- ^ Binary functions.
   , _arbFuns            :: [(Id, HsType)]                           -- ^ Unary/binary functions whose input types are members of the Arbitrary type class.
   , _benchFuns          :: [(Id, HsType)]                           -- ^ Unary/binary functions whose input types are members of the NFData type class.
   , _nfFuns             :: [(Id, HsType)]                           -- ^ Unary/binary functions whose result types are members of the NFData type class.
   , _invalidData        :: [(Id, HsType, [InputError])]             -- ^ Invalid user-specified test data. 
   , _unaryData          :: [(Id, HsType)]                           -- ^ Valid user-specified test data for unary functions.
   , _binaryData         :: [(Id, HsType)]                           -- ^ Valid user-specified test data for binary functions.
   , _invalidTestSuites  :: [(Id, [InputError])]                     -- ^ Invalid test suites.
   , _testSuites         :: [(Id, TestSuite)]                        -- ^ Valid test suites.
   }

instance Show UserInputs where 
  show = PP.render . docUserInputs

-- | Initialise a 'UserInputs' data structure by specifying the '_allElems' 
-- list. 
initUserInputs :: [(ModuleElem, Maybe TypeString)] -> UserInputs
initUserInputs xs = 
  UserInputs
    {
      _allElems          = xs
    , _invalidElems      = []
    , _validElems        = []
    , _nullaryFuns       = []
    , _unaryFuns         = []
    , _binaryFuns        = []
    , _arbFuns           = []
    , _benchFuns         = []
    , _nfFuns            = []
    , _invalidData       = []
    , _unaryData         = []
    , _binaryData        = []
    , _invalidTestSuites = []
    , _testSuites        = []
    }

-- * Benchmarking

-- * Statistical analysis

-- | The system approximates the time complexity of test programs by 
-- measuring their runtimes on test data of increasing size. Runtime 
-- measurements and input sizes are then given as (x, y)-coordinates
-- (x = size, y = runtime). Regression analysis (ridge regression) is used to 
-- fit various models (i.e., different types of functions: constant, linear, 
-- quadratic etc.) to the (x, y)-coordinates. Models are then compared to 
-- determine which has the best fit. The equation of the best fitting model is 
-- used as an approximation of time complexity. 
--
-- The 'LinearType' datatype describes which linear functions can be used as 
-- models. The system currently supports the following types of functions:
--
-- * Poly 0 (constant)     := a_0 
-- * Poly 1 (linear)       := a_0 + a_1 * x^2      
-- * Poly n                := a_0 + a_1 * x^1 + a_2 * x^2 + .. + a_n * x^n 
-- * Log  b n              := a_0 + a_1 * log_b^1(x) + a_2 * log_b^2(x) + .. + a_n * log_b^n(x)
-- * PolyLog b n           := a_0 + a_1 * x^1 * log_b^1(x) + a_2 * x^2 * log_b^2(x) + .. + a_n * x^n * log_b^n(x) 
-- * Exp n                 := a_0 + n^x
data LinearType = 
    Poly    Int        -- ^ Polynomial functions (Poly 0 = constant, Poly 1 = linear).
  | Log     Int Int    -- ^ Logarithmic functions.
  | PolyLog Int Int    -- ^ Polylogarithmic functions.     
  | Exp     Int        -- ^ Exponential function.
    deriving (Eq, Generic)

instance NFData LinearType

instance Show LinearType where 
  show (Poly      0) = "constant"
  show (Poly      1) = "linear"
  show (Poly      2) = "quadratic"
  show (Poly      3) = "cubic"
  show (Poly      4) = "quartic"
  show (Poly      5) = "quintic"
  show (Poly      6) = "sextic"
  show (Poly      7) = "septic"
  show (Poly      8) = "octic"
  show (Poly      9) = "nonic"
  show (Poly      n) = "n" ++ superNum n
  show (Log     b n) = "log" ++ subNum b ++ superNum n ++ "n"
  show (PolyLog b n) = "n" ++ superNum n ++ "log" ++ subNum b ++ superNum n ++ "n"
  show (Exp       n) = show n ++ "\x207F"

data Stats = Stats {} 

-- | Number of predictors for each type of model.
numPredictors :: LinearType -> Int 
numPredictors (Poly      k) = k + 1 
numPredictors (Log     _ k) = k + 1 
numPredictors (PolyLog _ k) = k + 1 
numPredictors Exp{}         = 2

-- * Errors 

-- | Errors raised by the system due to implementation failures. These can be 
-- generated at any time but are usually used to report unexpected IO results. 
-- For example, when dynamically checking user inputs (see 
-- 'AutoBench.Internal.UserInputChecks'), system errors are used to relay 
-- 'InterpreterError's thrown by functions in the hint package in cases
-- where the system didn't expect errors to result.
data SystemError = InternalErr String

instance Show SystemError where 
  show (InternalErr s) = "Internal error: " ++ s ++ "\nplease report on GitHub."

instance Exception SystemError

-- ** Input errors

-- | Input errors are generated by the system while analysing user input 
-- files. Examples input errors include erroneous test options, invalid test 
-- data, and test programs with missing Arbitrary/NFData instances.
--
-- In general, the system always attempts to continue with its execution for as 
-- long as possible. Therefore, unless a critical error is encountered, such as 
-- a filepath or file access error, it will collate all non-critical input 
-- errors. These will then be summarised after the user input file has been 
-- fully analysed.
data InputError = 
    FilePathErr  String    -- ^ Invalid filepath.
  | FileErr      String    -- ^ File access error.
  | TestSuiteErr String    -- ^ Invalid test suite.
  | DataOptsErr  String    -- ^ Invalid data options.
  | AnalOptsErr  String    -- ^ Invalid statistical analysis options.
  | TypeErr      String    -- ^ Invalid type signature.
  | InstanceErr  String    -- ^ One or more missing instances

instance Show InputError where 
  show (FilePathErr  s) = "File path error: "        ++ s
  show (FileErr      s) = "File error: "             ++ s
  show (TestSuiteErr s) = "Test suite error: "       ++ s
  show (DataOptsErr  s) = "Test data error: "        ++ s
  show (AnalOptsErr  s) = "Analysis options error: " ++ s
  show (TypeErr      s) = "Type error: "             ++ s
  show (InstanceErr  s) = "Instance error: "         ++ s

instance Exception InputError

-- * Helpers 

-- | Generate a 'PP.Doc' for a 'TestSuite'. 
docTestSuite :: TestSuite -> PP.Doc                                                                        -- ** NEEDS COMMENTS ** 
docTestSuite ts = PP.vcat 
  [ 
    PP.hcat $ PP.punctuate (PP.text ", ") $ fmap PP.text $ _progs ts
  , PP.text $ show $ _dataOpts ts
  ]

-- | Generate a 'PP.Doc' for a 'UserInputs'.                                                               -- ** NEEDS COMMENTS ** 
docUserInputs :: UserInputs -> PP.Doc 
docUserInputs inps = PP.vcat $ PP.punctuate (PP.text "\n")
  [ PP.text "All module elements:"     PP.$$ (PP.nest 2 $ showElems             $ _allElems          inps)
  , PP.text "Valid module elements:"   PP.$$ (PP.nest 2 $ showTypeableElems     $ _validElems        inps)
  , PP.text "Nullary functions:"       PP.$$ (PP.nest 2 $ showTypeableElems     $ _nullaryFuns       inps)
  , PP.text "Unary functions:"         PP.$$ (PP.nest 2 $ showTypeableElems     $ _unaryFuns         inps)
  , PP.text "Binary functions:"        PP.$$ (PP.nest 2 $ showTypeableElems     $ _binaryFuns        inps)
  , PP.text "Benchmarkable functions:" PP.$$ (PP.nest 2 $ showTypeableElems     $ _benchFuns         inps)
  , PP.text "Arbitrary functions:"     PP.$$ (PP.nest 2 $ showTypeableElems     $ _arbFuns           inps)
  , PP.text "NFData functions:"        PP.$$ (PP.nest 2 $ showTypeableElems     $ _nfFuns            inps)
  , PP.text "Unary test data:"         PP.$$ (PP.nest 2 $ showTypeableElems     $ _unaryData         inps)
  , PP.text "Binary test data:"        PP.$$ (PP.nest 2 $ showTypeableElems     $ _binaryData        inps)
  , PP.text "Test suites:"             PP.$$ (PP.nest 2 $ showTestSuites        $ _testSuites        inps)
  , PP.text "Invalid module elements:" PP.$$ (PP.nest 2 $ showElems             $ _invalidElems      inps)
  , PP.text "Invalid test data:"       PP.$$ (PP.nest 2 $ showInvalidData       $ _invalidData       inps)
  , PP.text "Invalid test suites:"     PP.$$ (PP.nest 2 $ showInvalidTestSuites $ _invalidTestSuites inps)
  ]
  where 
    showElems :: [(ModuleElem, Maybe TypeString)] -> PP.Doc 
    showElems [] = PP.text "N/A"
    showElems xs = PP.vcat [showDs, showCs, showFs]
      where 
        ((fs, tys), cs, ds) = foldr splitShowModuleElems (([], []), [], []) xs

        showDs | null ds   = PP.empty 
               | otherwise = PP.vcat [PP.text "Data:", PP.nest 2 $ PP.vcat $ fmap PP.text $ sort ds]
        showCs | null cs   = PP.empty 
               | otherwise = PP.vcat [PP.text "Class:", PP.nest 2 $ PP.vcat $ fmap PP.text $ sort cs]
        showFs | null fs   = PP.empty 
               | otherwise = PP.vcat [PP.text "Fun:", PP.nest 2 $ PP.vcat $ fmap PP.text $ sort $ zipWith (\idt ty -> idt ++ " :: " ++ ty) (deggar fs) tys]

    showTypeableElems :: [(Id, HsType)] -> PP.Doc
    showTypeableElems [] = PP.text "N/A"
    showTypeableElems xs = PP.vcat $ fmap PP.text $ sort $ zipWith (\idt ty -> idt ++ " :: " ++ prettyPrint ty) (deggar idts) tys
      where (idts, tys) = unzip xs

    showTestSuites :: [(Id, TestSuite)] -> PP.Doc 
    showTestSuites [] = PP.text "N/A"
    showTestSuites xs = PP.vcat $ fmap (uncurry showTestSuite) xs
      where 
        showTestSuite :: Id -> TestSuite -> PP.Doc 
        showTestSuite idt ts = PP.vcat 
          [ PP.text idt PP.<+> PP.text ":: TestSuite"
          , PP.nest 2 $ PP.vcat $ fmap PP.text (_progs ts)
          ]

    showInvalidData :: [(Id, HsType, [InputError])] -> PP.Doc
    showInvalidData [] = PP.text "N/A"
    showInvalidData xs = PP.vcat $ fmap showInvalidDat xs
      where 
        showInvalidDat :: (Id, HsType, [InputError]) -> PP.Doc
        showInvalidDat (idt, ty, errs) = PP.vcat 
          [ PP.text $ idt ++ " :: " ++ prettyPrint ty
          , PP.nest 2 $ PP.vcat $ fmap (PP.text . show) errs 
          ]

    showInvalidTestSuites :: [(Id, [InputError])]  -> PP.Doc 
    showInvalidTestSuites [] = PP.text "N/A"
    showInvalidTestSuites xs = PP.vcat $ fmap showInvalidTestSuite xs
      where 
        showInvalidTestSuite :: (Id, [InputError]) -> PP.Doc 
        showInvalidTestSuite (idt, errs) = PP.vcat 
          [ PP.text idt PP.<+> PP.text ":: TestSuite"
          , PP.nest 2 $ PP.vcat $ fmap (PP.text . show) errs 
          ]

    -- Helpers:

    splitShowModuleElems 
      :: (ModuleElem, Maybe TypeString)
      -> (([String], [String]), [String], [String]) 
      -> (([String], [String]), [String], [String])
    splitShowModuleElems (Fun idt, Just ty) ((fs, tys), cs, ds) = ((idt : fs, ty : tys), cs, ds)
    splitShowModuleElems (Fun idt, Nothing) ((fs, tys), cs, ds) = ((idt : fs, "" : tys), cs, ds)
    splitShowModuleElems (Class idt _, _) (fs, cs, ds) = (fs, idt : cs, ds)
    splitShowModuleElems (Data idt _, _)  (fs, cs, ds) = (fs, cs, idt : ds)