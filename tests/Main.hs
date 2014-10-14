{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}
import Test.Simple
import System.Environment (getArgs)
import System.Environment.Executable (getExecutablePath)
import System.Process (readProcessWithExitCode)
import Control.Monad.Trans (liftIO, lift)
import System.Exit (ExitCode(ExitSuccess))
import Control.Monad (guard)
import Test.QuickCheck (Gen, arbitrary, choose, stdArgs, quickCheckWithResult, Args(maxSuccess))
import Test.QuickCheck.Monadic

locTest :: TestSimpleT IO Bool
locTest = $loc >> ok False

testOk1 :: ExitCode -> String -> String -> TestSimpleT IO Bool
testOk1 ec out err = do
    is ec ExitSuccess
    is out "1..1\nok 1\n"
    is err ""

testUnknown :: ExitCode -> String -> String -> TestSimpleT IO Bool
testUnknown ec out err = do
    isnt ec ExitSuccess
    is out ""
    like err "Unknown"

testNOk1 :: ExitCode -> String -> String -> TestSimpleT IO Bool
testNOk1 ec out err = do
    isnt ec ExitSuccess
    like out "not ok 1"
    like err "# Hello\n"

testMismatch :: ExitCode -> String -> String -> TestSimpleT IO Bool
testMismatch ec _ err = do
    isnt ec ExitSuccess
    is err "# Looks like you planned 2 tests but ran 1.\n"

testIsFailure :: ExitCode -> String -> String -> TestSimpleT IO Bool
testIsFailure ec _ err = do
    isnt ec ExitSuccess
    like err "     got: 1\n"
    like err "expected: 2\n"

testLikeFailure :: ExitCode -> String -> String -> TestSimpleT IO Bool
testLikeFailure ec _ err = do
    isnt ec ExitSuccess
    like err "#               \"a\"\n"
    like err "# doesn't match \"b\"\n"

testUnlikeFailure :: ExitCode -> String -> String -> TestSimpleT IO Bool
testUnlikeFailure ec _ err = do
    isnt ec ExitSuccess
    like err "#         \"abc\""
    like err "# matches \"b\"\n"

testLocationPrint :: ExitCode -> String -> String -> TestSimpleT IO Bool
testLocationPrint ec _ err = do
    isnt ec ExitSuccess
    like err "  Failed test at tests/Main.hs line 14"
    like err "# Looks like you failed 1 test of 1.\n"

testMPlus :: ExitCode -> String -> String -> TestSimpleT IO Bool
testMPlus ec out err = do
    is ec ExitSuccess
    is err ""
    like out "1..2"

testMPlusFail :: ExitCode -> String -> String -> TestSimpleT IO Bool
testMPlusFail ec out err = do
    isnt ec ExitSuccess
    like err "failed 1 test of 2"
    like out "1..2"

testGuard :: ExitCode -> String -> String -> TestSimpleT IO Bool
testGuard ec out err = do
    isnt ec ExitSuccess
    like out "1..1"
    unlike err "DIAG"
    like err "#      got: 1\n"
    like err "# expected: anything else\n"

testEither :: ExitCode -> String -> String -> TestSimpleT IO Bool
testEither ec out err = do
    isnt ec ExitSuccess
    like out "1..2"
    like out "ok 1"
    like err "got Left: \"badleft\""

testRunTS :: ExitCode -> String -> String -> TestSimpleT IO Bool
testRunTS ec out err = do
    is ec ExitSuccess
    is err ""
    is out "True\n1..1\n# Bar\nok 1\n"

testQCOK :: Int -> ExitCode -> String -> String -> TestSimpleT IO Bool
testQCOK n ec out _ = do
    is ec ExitSuccess
    is out $ "+++ OK, passed " ++ show n ++ " tests.\n"

testQCFail :: ExitCode -> String -> String -> TestSimpleT IO Bool
testQCFail ec out _ = do
    isnt ec ExitSuccess
    like out "not ok 2"
    like out "Failed!"
    like out "1..2"
    like out "# Foo: False at unknown location."

testPropFail :: ExitCode -> String -> String -> TestSimpleT IO Bool
testPropFail ec out _ = do
    isnt ec ExitSuccess
    like out "not ok 1"
    like out "Failed! Assertion"

testAll :: IO ()
testAll = testSimpleMain $ do
    plan 59
    pn <- liftIO getExecutablePath
    mapM_ (runMyself pn) [ ("bbbf", testUnknown), ("ok1", testOk1), ("nok1", testNOk1)
                , ("mism", testMismatch), ("isf", testIsFailure)
                , ("likef", testLikeFailure), ("qloc", testLocationPrint)
                , ("unlike", testOk1), ("fail_unlike", testUnlikeFailure)
                , ("guard", testOk1), ("mplus", testMPlus), ("fail_mplus", testMPlusFail)
                , ("guardisnt", testGuard), ("either", testEither)
                , ("runts", testRunTS), ("qcrunok", testQCOK 100), ("qcfail", testQCFail)
                , ("qcmonok", testQCOK 5), ("qcmonfail", testPropFail) ]
    where runMyself pn (arg, act) = do
                (ec, out, err) <- liftIO $ readProcessWithExitCode pn [ arg ] ""
                act ec out err

identTS :: TestSimpleT Gen ()
identTS = plan 1 >> ok True >> return ()

propMon :: TestSimpleT (PropertyM IO) ()
propMon = plan 1 >> ok True >> return ()

failQC :: TestSimpleT Gen Bool
failQC = do
    plan 2
    i <- lift $ choose (1 :: Int, 5)
    ok (i > 0)
    b <- diagen "Foo" arbitrary
    ok b

propFail :: TestSimpleT (PropertyM IO) Bool
propFail = do
    plan 1
    ok False

main :: IO ()
main = do
    as <- getArgs
    case as of
        [] -> testAll
        [ "ok1" ] -> testSimpleMain $ plan 1 >> ok True
        [ "nok1" ] -> testSimpleMain $ plan 1 >> diag "Hello" >> ok False
        [ "mism" ] -> testSimpleMain $ ok True >> plan 2
        [ "isf" ] -> testSimpleMain $ is 1 (2::Int) >> plan 1
        [ "likef" ] -> testSimpleMain $ plan 1 >> like "a" "b"
        [ "qloc" ] -> testSimpleMain $ plan 1 >> locTest
        [ "unlike" ] -> testSimpleMain $ plan 1 >> unlike "abc" "d"
        [ "fail_unlike" ] -> testSimpleMain $ unlike "abc" "b"
        [ "guard" ] -> testSimpleMain $ plan 1 >> ok True >> guard False >> ok False
        [ "mplus" ] -> testSimpleMain $ (plan 1 >> ok True) >> (plan 1 >> ok True)
        [ "fail_mplus" ] -> testSimpleMain $ (plan 1 >> ok False) >> (plan 1 >> ok True)
        [ "guardisnt" ] -> testSimpleMain $ plan 1 >> (isnt (1::Int) 1 >>= guard) >> diag "DIAG"
        [ "either" ] -> testSimpleMain $ do
                            plan 2
                            isRight (Right "hhh" :: Either Int String)
                            isRight (Left "badleft" :: Either String Int)
        [ "runts" ] -> do
            (b, lg) <- runTestSimple $ plan 1 >> diag "Bar" >> ok True
            putStrLn $ show b
            mapM_ putStrLn lg
        [ "qcrunok" ] -> qcTestSimpleMain identTS
        [ "qcfail" ] -> qcTestSimpleMain failQC
        [ "qcmonok" ] -> qcTestSimpleWith (quickCheckWithResult $ stdArgs { maxSuccess = 5 })
                                propMon
        [ "qcmonfail" ] -> qcTestSimpleMain propFail
        _ -> error $ "Unknown: " ++ show as

