# An AutoBench Primer

Anyone who has read the system's introductory paper "AutoBench: comparing the time performance of Haskell programs" is advised to skip straight to the quick start guide. This primer should suffice for anyone else who wants a quick summary of the system.

Suppose we are given two Haskell programs that reverse lists of integers:

```
slowRev :: [Int] -> [Int]
slowRev []       = []
slowRev (x : xs) = slowRev xs ++ [x]

fastRev :: [Int] -> [Int]
fastRev xs = go xs []
  where 
    go [] ys       = ys 
    go (x : xs) ys = go xs (x : ys)
```

How can we compare them? Firstly, we may want to check that they give the same results. To do so we can use QuickCheck:

```
GHCi> quickCheck (\xs -> slowRev xs == fastRev xs)
+++ OK, passed 100 tests.
```

Here QuickCheck has generated 100 random input lists and checked that `slowRev` and `fastRev` give the same results for all test cases.

Secondly, we may want to check which is faster. To do this we can use GHCi's timing/memory stats:

```
GHCi> :set +s 
GHCi> slowRev [1..100]
[100,99,98,98...
(0.01 secs, 635,640 bytes)
GHCi> fastRev [1..100]
[100,99,98,98...
(0.01 secs, 368,776 bytes)
```

From these results we can see that `slowRev` is using more memory, but the times are the same. Maybe we could try bigger lists?

```
GHCi> slowRev [1..100000]
[100000,99999,99998,99997,99996,99995,99994...
```
Who wants to wait for all that printing to finish? Also printing is time consuming and will affect the measured runtimes. Maybe we can suppress the printing of results? To do this we can use `seq` to force the computation and then return `()`.

```
GHCi> slowRev [1..100000] `seq` ()
()
(0.05 secs, 29,933,880 bytes)
GHCI> fastRev  [1..100000] `seq` ()
()
(0.04 secs, 19,284,568 bytes)
```

That seems to work, and the first test result suggests that `fastRev` is faster (no surprises there). But one test case should not be enough to convince us that `fastRev` is indeed faster. After all, QuickCheck uses (at least) 100 to check that both functions return the same results! Doing a large number of manual tests seems tedious, if only there was a way to automate it...

AutoBench does exactly this. It generates random test inputs of different sizes using QuickCheck, benchmarks the runtimes of test programs executed on the data using Criterion, and compares the measured runtimes to check which program is faster. It also produces runtime graphs, and approximates the time complexity of each test program using regression analysis.

Invoking `./AutoBench "Input.hs"`, where `Input.hs` is in the working directory and defined:

```
module Input where 

import Data.Default (def)
import AutoBench.QuickCheck
import AutoBench.Types

slowRev :: [Int] -> [Int]
slowRev []       = []
slowRev (x : xs) = slowRev xs ++ [x]

fastRev :: [Int] -> [Int]
fastRev xs = go xs []
  where 
    go [] ys       = ys 
    go (x : xs) ys = go xs (x : ys)

ts :: TestSuite 
ts  = def
```

gives the following performance results. 

Printed to the console:

```
 ―― Test summary ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――

  Programs       fastRev, slowRev
  Data           Random, size range [0,5..100]
  Normalisation  nf
  QuickCheck     ✔
  GHC flags      n/a

 ―― Analysis ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――

  fastRev
    Size          0       5       10      15      20      25      30      35
                  40      45      50      55      60      65      70      75
                  80      85      90      95      100
    Time    (μs)  0.022   0.055   0.091   0.131   0.166   0.207   0.241   0.287
                  0.332   0.361   0.398   0.441   0.475   0.509   0.552   0.588
                  0.623   0.670   0.705   0.739   0.784
    Std dev (μs)  0.004
    Average variance introduced by outliers: 30% (moderately inflated)

    Fits          y = 1.62e-8 + 7.65e-9x
                  y = 7.65e-8 + 1.09e-9xlog₂(x)
                  y = 2.00e-7 - 1.71e-7log₂(x) + 3.77e-8log₂²(x)

  slowRev
    Size          0       5       10      15      20      25      30      35
                  40      45      50      55      60      65      70      75
                  80      85      90      95      100
    Time    (μs)  0.021   0.141   0.424   0.858   1.490   2.249   3.194   4.292
                  5.556   6.941   8.530   10.30   12.14   14.20   16.63   18.79
                  21.40   24.12   26.86   29.96   33.20
    Std dev (μs)  0.122
    Average variance introduced by outliers: 14% (moderately inflated)

    Fits          y = 2.56e-7 + 3.32e-11x + 3.30e-9x²
                  y = 2.45e-12 + 1.02e-10x + 3.46e-9x² - 1.46e-12x³
                  y = 9.35e-16 + 4.80e-14x + 2.33e-12x² + 8.92e-11x³
                      - 5.72e-13x⁴

  Optimisation:

    slowRev ≥ fastRev (0.95)

 ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
```

Output to file:

![Reversing.png](Use%20Cases/Reversing/Reversing.png)


It is important to note that there are a number of issues to address when benchmarking the runtimes of programs executed on random inputs generated by QuickCheck using Criterion. These are explained in detail in the system's introductory paper "AutoBench: comparing the time performance of Haskell programs".

# AutoBench Quick Start Guide


## Installing and Invoking AutoBench

Get AutoBench up and running in five steps:

1. Download the source files from this GitHub repository;
2. Run `cabal install AutoBench` in a cabal sandbox;
4. Copy and paste the code from the primer above and save it to a file called `Input.hs` in the same directory as the `AutoBench` binary you compiled in step 2;
5. Run `./AutoBench "Input.hs"`

## Test Files
Test files are simply Haskell modules that contain test programs, test data generators (or user-specified test data), and test suites. These are referred to collectively as *test inputs*, and are explained in the following subsection.

### Test Inputs
#### Test Suites

`TestSuite`s are AutoBench's principle user input datatype, and are used to structure performance tests into logical units that can be checked, validated, and executed independently. 

An advantage of this approach is that users can group multiple test suites in the same file according to some testing context, whether it be analysing the performance of the same programs subject to different levels of optimisation, or comparing different implementations under the same test conditions. Another advantage is that if one or more test suites in a user input file are erroneous, other, valid test suites in the same file can be executed nonetheless.

`TestSuite`s are constructed as follows:

* `_progs  :: [String]`: The so-called *progs* list contains the names of the programs to be tested. Each program in the list must be defined in the same file as the `TestSuite`. All programs should have the same type, and that type must be compatible with the remainder of the `TestSuite`'s settings. For example, if `_nf = True`, then the result type of test programs must be a member of the `NFData` type class. If `_dataOpts = Gen ...`, then the input type of test programs must be a member of the `Arbitrary` type class. Users can specify an empty `_progs` list, in which case all programs in the input file will be considered for testing: zero or more test suites will be generated with non-empty `_progs` lists satisfying the remainder of the `TestSuite`s settings. (The system effectively fills in the details on behalf of users.)
* `_dataOpts :: DataOpts`: Test data options specify which test data to use. Users have two options: provide their own test data `Manual "..."`or have the system generate random inputs`Gen ...`. See Test Data for more information. Again, the types of the test programs must be compatible with this setting, for example, `Gen ...` requires the input types of test programs be members of the`Arbitrary` type class.
* `_analOpts :: AnalOpts`: A large number of user options for statistical analysis. These options include: which types of functions to use as models for regression analysis (when approximating the time complexity of each test program); functions to calculate improvement results, functions to filter and compare regression models based on fitting `Stats` produced by the system. See Statistical Analysis for more information.
* `_critCfg :: Criterion.Config`: Criterion's configuration. When benchmarks are executed by Criterion, this configuration is used. This allows users to configure Criterion as if it was being used directly. Note: the default configuration works just fine and this option is mainly for users who wish to generate Criterion reports as well AutoBench reports.
* `_baseline :: Bool`: Whether the system should produce baseline measurements. These measure the time spent evaluating the *results* of test programs to normal form. This can be useful if the runtimes of test programs look odd. For example, if the identity function is tested on lists of integers and test cases are evaluated to normal form, the system will approximate `id` as linear. However, it clearly has constant time complexity. The linear factor comes from the time spent normalising each 
result list. This can be seen using baseline measurements. Note: the baseline setting can only be used in conjunction with the `_nf = True` setting.
* `_nf :: Bool`: Whether test cases should be evaluated to normal form `True` or weak head normal form `False`. Typically test cases should be evaluated to normal form to ensure the full cost of applying each test program is reflected in runtime measurements.
* `_ghcFlags :: [String]`: Any GHC compiler flags to use when compiling benchmarking files. For example, users can specify optimisation flags`-O2` `-O3`. Note: invalid flags are ignored but displayed to users as warnings.

All `TestSuite`options and settings are carefully validated. All errors are reported to users and invalid `TestSuite`s cannot be run by the system. The system provides the following default `TestSuite`:

```
def :: TestSuite
def  = 
   { _progs     = [] 
   , _dataOpts  = def 
   , _analOpts  = def
   , _critCfg   = Criterion.Main.Options.defaultConfig
   , _baseline  = False
   , _nf        = True
   , _ghcFlags  = [] 
   }
```
Important note: the most basic check that the system performs on every test suite is to ensure that each of its record fields are initialised. Ensure test suites are fully defined.

#### Test Data
##### Random Test Data

Random test data can generated automatically by the system. If test data should be generated by the system, users must specify the size of the data to be generated. This is achieved using `Gen l s u`, which specifies as a size *range* by a lower bound `l`, an upper bound `u`, and a step `s`. This is converted to a Haskell range `[l, (l + s) .. u]` and a test input is generated for each size in this list. For example: `Gen 0 5 100` corresponds to the range `[0, 5, 10 .. 100]`. Concrete example:

```
tProg :: [Int] -> [Int]
tProg  = ...

ts :: TestSuite 
ts  = def { _progs = ["tProg"], _dataOpts = Gen 0 5 100 }
```

The default test data options are as follows:

```
def :: DataOpts
def  = Gen 0 5 100
```
##### User-specified Test Data

Due to certain benchmarking requirements, test data must be specified in the IO monad. In addition, the system cannot determine the size of user-specified test data automatically. As such, for a test program `p :: a -> b` , user-specified test data is of type `[(Int, IO a)]` where the first element of each tuple is the size of the test input, and the second element is the input itself. Concrete example:

```
tDat :: UnaryTestData [Int]
tDat  = 
  [ ( 5, return [1,2,3,4,5])
  , (10, return [1,2,3,4,5,6,7,8,9,10])
  ... 
  ]
```

Here the size of each `[Int]` is determined by its number of elements: `5` and `10`, respectively.

If users choose to specify their own inputs, then the `Manual ...` data option simply tells the system the name of the test data in the test file. Concrete example:

```
tProg :: [Int] -> [Int]
tProg  = ...

tDat :: UnaryTestData [Int]
tDat  = ...

ts :: TestSuite 
ts  = def { _progs = ["tProg"], _dataOpts = Manual "tDat" }
```

#### Statistical Analysis Options

The system provides a number of user options for statistical analysis.

`AnalOpts`s are constructed as follows:

* `_linearModels :: [LinearType]`: Which types of functions to consider for regression analysis;
* `_cvIters :: Int`: The number of iterations of cross-validation to perform;
* `_cvTrain :: Double`: The percentage of test data to use as training data for cross-validation;
* `_topModels :: Int`: The number of models to review when selecting the best fitting model from the results of regression analysis;
* `_statsFilt :: Stats -> Bool   `: A function to discard models that \"do not\" fit a given data set based on the fitting statistics produced by the system;
* `_statsSort :: Stats -> Stats -> Ordering`: A function to rank models according to how they fit a given data set based on the fitting statistics produced by the system;
* `_improv :: [(Double, Double)] -> Maybe (Ordering, Double)`: A function to calculate efficiency improvement results by comparing the runtimes of two test programs pointwise.
* `_graphFP :: Maybe FilePath` : A PNG graph of runtime measurements with complexity estimates plotted as lines of best fit;
* `_reportFP :: Maybe FilePath`: A TXT performance report;
* `_coordsFP :: Maybe FilePath`: A CSV of (input size(s), runtime) coordinates for each test program.

The system provides the following default `AnalOpts`:

``` 
def :: AnalOpts
def  = 
  {
    _linearModels = [ Poly 0, Poly 1, Poly 2, Poly 3, Poly 4  
                    , Log 2 1, Log 2 2
                    , PolyLog 2 1
                    , Exp 2 
                    ]
  , _cvIters   = 200
  , _cvTrain   = 0.7
  , _topModels = 3
  , _statsFilt = defaultStatsFilt 
  , _statsSort = defaultStatsSort                  
  , _improv    = defaultImprov
  , _graphFP   = Just "./AutoBenched.png"  
  , _reportFP  = Nothing                          
  , _coordsFP  = Nothing
  }
```

#### Other Important Notes
* All test programs *must* have an `NFData` instance for their input types;
* Pay close attention to the details of the `_progs :: [String]` list;
* The module names of test files **must** match the filename. For example, a test file named `Input.hs` must have `module Input where` at the top of the file. This is a basic system requirement;
* Test suites require a minimum number of 20 *distinctly sized* test inputs;
* While getting to grips with the system, the default options should be sufficient;
* See comments in `AutoBench.Types` for more details on the above user options;
* **Incorrectly sized test data will lead to erroneous performance results**.










