import XCTest
@testable import Budget

final class AmountExpressionTests: XCTestCase {
    private func eval(_ text: String) -> Decimal? { AmountExpression.evaluate(text) }

    func testPlainNumbers() {
        XCTAssertEqual(eval("12"), 12)
        XCTAssertEqual(eval("12,5"), Decimal(string: "12.5"))
        XCTAssertEqual(eval("12.5"), Decimal(string: "12.5"))
        XCTAssertEqual(eval("1 234,56 €"), Decimal(string: "1234.56"))
    }

    func testOperatorsAndPrecedence() {
        XCTAssertEqual(eval("12+8,5"), Decimal(string: "20.5"))
        XCTAssertEqual(eval("10-3-2"), 5)
        XCTAssertEqual(eval("2+3*4"), 14)
        XCTAssertEqual(eval("(2+3)*4"), 20)
        XCTAssertEqual(eval("20/4"), 5)
        XCTAssertEqual(eval("(3×4,20)+2"), Decimal(string: "14.6"))
        XCTAssertEqual(eval("3x2"), 6)
        XCTAssertEqual(eval("9÷3"), 3)
        XCTAssertEqual(eval("10−4"), 6)
    }

    func testUnaryAndRounding() {
        XCTAssertEqual(eval("-5"), -5)
        XCTAssertEqual(eval("+5"), 5)
        XCTAssertEqual(eval("10/3"), Decimal(string: "3.33"))
        XCTAssertEqual(eval("0,005"), Decimal(string: "0.01"))
    }

    func testInvalidExpressions() {
        XCTAssertNil(eval(""))
        XCTAssertNil(eval("abc"))
        XCTAssertNil(eval("1+"))
        XCTAssertNil(eval("(1+2"))
        XCTAssertNil(eval("1/0"))
        XCTAssertNil(eval("1..2+"))
    }

    func testSpacesInsideNumbersAreThousandsSeparators() {
        XCTAssertEqual(eval("1 234"), 1234)
    }

    func testPositiveAmount() {
        XCTAssertEqual(AmountExpression.positiveAmount("3+4"), 7)
        XCTAssertNil(AmountExpression.positiveAmount("0"))
        XCTAssertNil(AmountExpression.positiveAmount("-3"))
        XCTAssertNil(AmountExpression.positiveAmount("x"))
    }

    func testContainsOperator() {
        XCTAssertFalse(AmountExpression.containsOperator("12,5"))
        XCTAssertFalse(AmountExpression.containsOperator("-12"))
        XCTAssertTrue(AmountExpression.containsOperator("12+3"))
        XCTAssertTrue(AmountExpression.containsOperator("(12)"))
    }
}
