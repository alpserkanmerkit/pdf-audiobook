// Oracle RED test (2026-09-28 night, measurement report §2, case T3_uzun):
// the reviewer returned the text completing cut #36 (Deniz) with `index: 35`;
// applyReviewCorrections wrote it to #35 (Emel) -> Emel's original 4 sentences were DELETED,
// and Emel started talking about herself as "Emel's ... criticism".
// Root cause: (1) the party sent to the reviewer has no index, the model counts the turns
// itself (llm_discussion.dart _reviewRawContent); (2) applyReviewCorrections writes the text
// WITHOUT checking its RELEVANCE to the target turn (discussion_review.dart).
//
// Pinned contract (design decision: reject, don't guess): if a correction text carries the
// content of ANOTHER turn (>= 60% of that turn's content words are in the correction AND more
// than in the target), the correction is REJECTED and the target stays as it is. The reviewer
// may under no circumstances change the speaker order, identity or turn count.
import 'package:flutter_test/flutter_test.dart';
import 'package:sesli_kitap/src/discussion/discussion_review.dart';
import 'package:sesli_kitap/src/discussion/discussion_turn.dart';

// Verbatim from the raw T3_uzun output (olcum_out/T3_uzun_yazar.txt #34-#36).
const String _t34Kaya =
    'Ahmet, o açtığını iddia ettiğin vanaların hiçbirinin nesnel bir '
    'göstergesi yok elimizde. İrma rüyasının analizinde hekimin bir '
    'meslektaşına duyduğu haset ile çocukluk anıları arasında kurulan bağ '
    'tamamen rüya sahibinin kişisel beyanına dayanıyor; laboratuvarda '
    'ölçülebilir, tekrarlanabilir tek bir veri bile sunamıyorsun. Bir '
    'yöntemin bilimsel olabilmesi için rüya sahibinin keyfi çağrışımlarına '
    'değil, bağımsız gözlemcinin doğrulayabileceği parametrelere dayanması '
    'gerekir. Senin savunduğun yöntem hastanın kendi kendini ikna etme '
    'ritüelinden öteye geçemiyor.';
const String _t35Emel =
    "Kaya'nın bu vurgusu tartışmanın düğüm noktasıdır: Ahmet'in yöntemi, "
    'rüya sahibinin kendi çağrışımları dışında hiçbir kanıt kabul etmiyor. '
    'Üstelik bir çağrışım arzu doyumuna uymadığında, Ahmet hemen "orada '
    'direnç var" ya da "bu bir sansür kılığıdır" diyerek teorisini her türlü '
    'çürütülme riskine karşı zırhla kaplıyor. Bilimsel bir yöntem '
    'yanlışlanabilir olmak zorundadır; her kapıyı açan bir anahtar aslında '
    'hiçbir kilidi gerçekten açmıyor demektir. Travma rüyaları, gün '
    'kalıntılarının somut baskısı ve nörolojik veriler ortadayken, tüm '
    'rüyaları tek bir arzu kalıbına dökmek apaçık bir dogmatizmdir.';
const String _t36DenizKesik =
    "Emel'in yanlışlanabilirlik eleştirisi Ahmet'in katı arzu formülünü "
    'tam merkezinden vuruyor ama vardığı sonuç yine eksik';
// T3_uzun_reviewer.txt: {"index": 35, "text": <this>} -- the completion of #36.
const String _reviewerMetni =
    "Emel'in yanlışlanabilirlik eleştirisi Ahmet'in katı arzu formülünü "
    'tam merkezinden vuruyor ama vardığı sonuç yine eksik kalıyor. Rüya '
    'bilimsel bir laboratuvar deneyi olmadığı için onu sadece '
    'yanlışlanabilirlik terazisinde tartamazsınız. Zihin her gece kendi '
    'varoluşsal tiyatrosunu kurarak insanın trajik hakikatini sahneler.';

const List<DiscussionTurn> _t3 = [
  DiscussionTurn(DiscussionSpeaker.d, _t34Kaya),
  DiscussionTurn(DiscussionSpeaker.b, _t35Emel),
  DiscussionTurn(DiscussionSpeaker.c, _t36DenizKesik),
];

ReviewResult _fix(int index, String text) => ReviewResult(
  ok: false,
  corrections: [ReviewCorrection(index: index, text: text)],
);

void main() {
  group('correction written to the wrong index is REJECTED (T3 case)', () {
    test("if Deniz's completed turn arrives at Emel's index, "
        "Emel's original turn stays UNCHANGED", () {
      // In T3 the reviewer said index 35; in this 3-turn slice Emel = 1.
      final result = applyReviewCorrections(_t3, _fix(1, _reviewerMetni));

      expect(result[1], const DiscussionTurn(DiscussionSpeaker.b, _t35Emel));
      expect(result, orderedEquals(_t3));
    });

    test('a correction that copies another turn text verbatim is also rejected '
        '(even if it is not the same speaker)', () {
      final result = applyReviewCorrections(_t3, _fix(0, _t35Emel));
      expect(result[0].text, _t34Kaya);
    });
  });

  group('legitimate corrections ARE applied (no over-rejection)', () {
    test('a completion at the correct index is applied', () {
      final result = applyReviewCorrections(_t3, _fix(2, _reviewerMetni));
      expect(
        result[2],
        const DiscussionTurn(DiscussionSpeaker.c, _reviewerMetni),
      );
      expect(result[1].text, _t35Emel);
    });

    test('NAME correction (a single word changes) is applied', () {
      final yeni = _t34Kaya.replaceFirst('Ahmet,', 'Emel,');
      final result = applyReviewCorrections(_t3, _fix(0, yeni));
      expect(result[0].text, yeni);
    });

    test('REWRITE correction (entirely new text) is applied', () {
      const yeni =
          'Travma geçiren askerlerin kâbusları her gece aynı sahneyi '
          'yineliyor. Bu tekrar bir dilek doyumu gibi görünmüyor. Zihin '
          'burada bir yarayı kapatmaya uğraşıyor olabilir.';
      final result = applyReviewCorrections(_t3, _fix(1, yeni));
      expect(result[1].text, yeni);
    });
  });

  group('invariant: speaker order, identity and turn count', () {
    test('mixed (valid + wrong-index + out-of-range + empty) corrections keep '
        'the same count and speaker order', () {
      final result = applyReviewCorrections(
        _t3,
        const ReviewResult(
          ok: false,
          corrections: [
            ReviewCorrection(index: 1, text: _reviewerMetni),
            ReviewCorrection(index: 2, text: _reviewerMetni),
            ReviewCorrection(index: 7, text: 'out of range'),
            ReviewCorrection(index: 0, text: '  '),
          ],
        ),
      );
      expect(result, hasLength(_t3.length));
      expect(result.map((t) => t.speaker), _t3.map((t) => t.speaker));
      expect(result[1].text, _t35Emel, reason: 'wrong index rejected');
      expect(result[2].text, _reviewerMetni, reason: 'correct index applied');
    });
  });

  group('reviewer prompt tells the model not to count the turns itself', () {
    test(
      'the prompt asks for the turn number to be written EXACTLY in the index field',
      () {
        expect(reviewerPrompt, contains('do not count it yourself'));
      },
    );
  });
}
